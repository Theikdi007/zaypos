using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence;

namespace ZayPOS.Infrastructure.Auth;

/// <summary>
/// Auth runs before the caller has a tenant (lookups by phone, device id,
/// refresh token), so this is the ONE class allowed to call IgnoreQueryFilters.
/// A test fails if it appears anywhere else.
/// </summary>
internal sealed class AuthRepository(ZayPosDbContext db) : IAuthRepository
{
    public Task<User?> FindUserByPhoneAsync(string phone, CancellationToken ct) =>
        db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(u => u.Phone == phone && u.DeletedAt == null, ct);

    public Task<User?> FindUserAsync(Guid userId, CancellationToken ct) =>
        db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(u => u.Id == userId, ct);

    public Task<Tenant?> FindTenantAsync(Guid tenantId, CancellationToken ct) =>
        db.Tenants.IgnoreQueryFilters().FirstOrDefaultAsync(t => t.Id == tenantId && t.DeletedAt == null, ct);

    public Task<Device?> FindDeviceAsync(Guid deviceId, CancellationToken ct) =>
        db.Devices.IgnoreQueryFilters().FirstOrDefaultAsync(d => d.Id == deviceId, ct);

    public async Task<IReadOnlyList<string>> DeviceCodesAsync(Guid tenantId, CancellationToken ct) =>
        await db.Devices.IgnoreQueryFilters().Where(d => d.TenantId == tenantId).Select(d => d.Code).ToListAsync(ct);

    public Task<int> CountOtpsSinceAsync(string phone, DateTime since, CancellationToken ct) =>
        db.OtpChallenges.CountAsync(o => o.Phone == phone && o.CreatedAt > since, ct);

    public Task<OtpChallenge?> FindOpenOtpAsync(string phone, OtpPurpose purpose, DateTime now, int maxAttempts, CancellationToken ct) =>
        db.OtpChallenges
            .Where(o => o.Phone == phone && o.Purpose == purpose && o.ConsumedAt == null
                        && o.ExpiresAt > now && o.Attempts < maxAttempts)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);

    public Task<RefreshToken?> FindRefreshTokenAsync(byte[] tokenHash, CancellationToken ct) =>
        db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == tokenHash, ct);

    public async Task<bool> TryRevokeRefreshTokenAsync(Guid tokenId, Guid? replacedById, DateTime now, CancellationToken ct) =>
        await db.RefreshTokens
            .Where(t => t.Id == tokenId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now).SetProperty(t => t.ReplacedById, replacedById), ct) == 1;

    public Task RevokeRefreshTokensAsync(Guid userId, Guid? deviceId, DateTime now, CancellationToken ct) =>
        db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null && (deviceId == null || t.DeviceId == deviceId))
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);

    public void Add<T>(T entity) where T : class => db.Add(entity);

    public void Discard<T>(T entity) where T : class => db.Entry(entity).State = EntityState.Detached;

    public async Task SaveChangesAsync(CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException e) when (e.InnerException is SqlException { Number: 2601 or 2627 } sql)
        {
            throw new UniqueViolationException(sql.Message, e);
        }
    }

    public async Task<IAuthTransaction> BeginTransactionAsync(CancellationToken ct) =>
        new Transaction(await db.Database.BeginTransactionAsync(ct));

    private sealed class Transaction(IDbContextTransaction tx) : IAuthTransaction
    {
        public Task CommitAsync(CancellationToken ct) => tx.CommitAsync(ct);
        public ValueTask DisposeAsync() => tx.DisposeAsync();
    }
}
