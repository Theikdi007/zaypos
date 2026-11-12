using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Account;

public sealed record MeResponse(MeUser User, MeTenant Tenant, IReadOnlyDictionary<string, bool> Features, PlanInfo Plan,
    IReadOnlyList<DeviceInfoDto> Devices, Guid CurrentDeviceId);

public sealed record MeUser(Guid Id, string Name, string Phone, UserRole Role);

public sealed record MeTenant(Guid Id, string Name, string TemplateId, string? Township, string Phone, DateTime CreatedAt);

/// <summary><see cref="Active"/> = what the app should unlock now (pro and not expired).</summary>
public sealed record PlanInfo(TenantPlan Plan, DateTime? ExpiresAt, TenantPlan Active)
{
    public static PlanInfo Of(Tenant t, DateTime now) =>
        new(t.Plan, t.PlanExpiresAt, t.Plan == TenantPlan.Pro && (t.PlanExpiresAt is null || t.PlanExpiresAt > now) ? TenantPlan.Pro : TenantPlan.Free);
}

public sealed record DeviceInfoDto(Guid Id, string Code, string? Name, int LastSeq, DateTime? LastSyncAt, DateTime CreatedAt, bool IsCurrent);

/// <summary>GET /me, GET /devices, DELETE /devices/{id} (README §5). Tenant scope = global query filter.</summary>
public sealed class AccountService(IAppDb db, TimeProvider clock)
{
    private DateTime Now => SyncJson.ToUtcMs(clock.GetUtcNow().UtcDateTime);

    public async Task<MeResponse> MeAsync(SyncCaller caller, CancellationToken ct)
    {
        var user = await db.Set<User>().AsNoTracking().FirstOrDefaultAsync(u => u.Id == caller.UserId && u.DeletedAt == null, ct)
                   ?? throw new ApiException(401, "invalid_token", "The user of this token no longer exists.");
        var tenant = await db.Set<Tenant>().AsNoTracking().FirstAsync(t => t.Id == caller.TenantId, ct);

        // Every Dart flag is present: a key missing from the table means "off".
        var stored = await db.Set<TenantFeature>().AsNoTracking().ToDictionaryAsync(f => f.FeatureKey, f => f.Enabled, ct);
        var features = FeatureKeys.All.ToDictionary(k => k, k => stored.GetValueOrDefault(k));

        return new MeResponse(
            new MeUser(user.Id, user.Name, user.Phone, user.Role),
            new MeTenant(tenant.Id, tenant.Name, tenant.TemplateId, tenant.Township, tenant.Phone, tenant.CreatedAt),
            features,
            PlanInfo.Of(tenant, Now),
            await DevicesAsync(caller, ct),
            caller.DeviceId);
    }

    /// <summary>Active (not revoked) devices, oldest first.</summary>
    public async Task<IReadOnlyList<DeviceInfoDto>> DevicesAsync(SyncCaller caller, CancellationToken ct) =>
        await db.Set<Device>().AsNoTracking()
            .Where(d => d.DeletedAt == null)
            .OrderBy(d => d.CreatedAt).ThenBy(d => d.Code)
            .Select(d => new DeviceInfoDto(d.Id, d.Code, d.Name, d.LastSeq, d.LastSyncAt, d.CreatedAt, d.Id == caller.DeviceId))
            .ToListAsync(ct);

    /// <summary>
    /// Owner removes a lost phone: the device row is soft-deleted (other phones see it disappear on
    /// their next pull) and its refresh tokens are revoked, so it can't sync again. Its code is never
    /// reused, so receipt numbers stay unique. Idempotent.
    /// </summary>
    public async Task RevokeDeviceAsync(SyncCaller caller, Guid deviceId, CancellationToken ct)
    {
        if (deviceId == caller.DeviceId)
            throw new ApiException(409, "cannot_revoke_current_device", "Remove this phone from another device, or sign out instead.");

        var device = await db.Set<Device>().FirstOrDefaultAsync(d => d.Id == deviceId, ct)
                     ?? throw new ApiException(404, "not_found", "No such device in this shop.");
        if (device.DeletedAt is not null) return;

        var now = Now;
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        device.DeletedAt = now;
        device.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        await db.Set<RefreshToken>()
            .Where(t => t.DeviceId == deviceId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);
        await tx.CommitAsync(ct);
    }
}
