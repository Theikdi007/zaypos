using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Sync;

/// <summary>
/// POST /sync/push (README §3.1). Units are processed in order, each in its own
/// transaction, exactly once (ProcessedUnits). Real-world events are never rejected;
/// only malformed units (bugs) are.
/// </summary>
public sealed class SyncPushService(IAppDb db, IDbErrors errors, TimeProvider clock)
{
    private const int MaxAttempts = 3;

    private DateTime Now => SyncJson.ToUtcMs(clock.GetUtcNow().UtcDateTime);

    public async Task<PushResponse> PushAsync(SyncCaller caller, PushRequest req, CancellationToken ct)
    {
        if (req.DeviceId != caller.DeviceId)
            throw new ApiException(403, "device_mismatch", "deviceId must be the device of the access token.");
        if (req.Units is not { Count: > 0 } units)
            throw new ApiException(400, "validation", "units must not be empty.");
        if (units.Count > SyncLimits.MaxUnitsPerPush)
            throw new ApiException(400, "validation", $"At most {SyncLimits.MaxUnitsPerPush} units per push.");
        if (units.Any(u => u.UnitId == Guid.Empty))
            throw new ApiException(400, "validation", "Every unit needs a unitId.");
        await SyncAccess.RequireActiveDeviceAsync(db, caller, ct);

        var results = new List<UnitResult>(units.Count);
        foreach (var unit in units)
            results.Add(await ProcessAsync(caller, unit, ct));

        db.ChangeTracker.Clear();
        var now = Now;
        await db.Set<Device>().Where(d => d.Id == caller.DeviceId)
            .ExecuteUpdateAsync(s => s.SetProperty(d => d.LastSyncAt, now), ct);

        return new PushResponse(results, Now);
    }

    private async Task<UnitResult> ProcessAsync(SyncCaller caller, PushUnit unit, CancellationToken ct)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await ApplyOnceAsync(caller, unit, ct);
            }
            catch (SyncRejectException e)
            {
                return await RecordRejectedAsync(caller, unit, e.Message, ct);
            }
            catch (Exception e) when (attempt < MaxAttempts && errors.Classify(e) is DbErrorKind.Concurrency or DbErrorKind.Unique)
            {
                // Another push touched the same rows (LWW rowversion conflict) or the same unit is being
                // applied concurrently (its PK collides): start over; step 1 then sees ProcessedUnits.
            }
            catch (Exception e) when (errors.Classify(e) is DbErrorKind.Unique or DbErrorKind.ForeignKey
                                          or DbErrorKind.Check or DbErrorKind.Truncation)
            {
                return await RecordRejectedAsync(caller, unit, "The database refused the unit: " + errors.Describe(e), ct);
            }
        }
    }

    private async Task<UnitResult> ApplyOnceAsync(SyncCaller caller, PushUnit unit, CancellationToken ct)
    {
        db.ChangeTracker.Clear();
        var now = Now;
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // 1. Idempotent retry → previous outcome.
        var done = await db.Set<ProcessedUnit>().AsNoTracking().FirstOrDefaultAsync(p => p.UnitId == unit.UnitId, ct);
        if (done is not null) return new UnitResult(unit.UnitId, done.Outcome, null, []);

        // 2. Shape.
        if (unit.Kind is null || !UnitKinds.All.Contains(unit.Kind))
            throw new SyncRejectException($"Unknown unit kind '{unit.Kind}'.");
        var rows = SyncJson.ParseRows(unit.Rows);
        var applier = new UnitApplier(db, caller, unit with { ClientTime = unit.ClientTime is { } t ? SyncJson.ToUtcMs(t) : null }, rows, now);

        // 3 + 4. Table rules, totals, business checks.
        var outcome = UnitOutcome.Applied;
        if (unit.Kind == UnitKinds.VoidSale && await applier.IsNoOpVoidAsync(ct))
        {
            outcome = UnitOutcome.Skipped;
            db.ChangeTracker.Clear();
        }
        else
        {
            await applier.ApplyAsync(ct);
            await applier.SaveAndCheckAsync(ct);
        }

        // 5. Remember, commit.
        db.Set<ProcessedUnit>().Add(new ProcessedUnit
        {
            TenantId = caller.TenantId, UnitId = unit.UnitId, DeviceId = caller.DeviceId, Outcome = outcome, ProcessedAt = now,
        });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        return new UnitResult(unit.UnitId, outcome, null, outcome == UnitOutcome.Applied ? applier.IssueKinds : []);
    }

    /// <summary>Nothing of the unit is kept; only the fact that it was rejected (so a retry answers the same).</summary>
    private async Task<UnitResult> RecordRejectedAsync(SyncCaller caller, PushUnit unit, string reason, CancellationToken ct)
    {
        db.ChangeTracker.Clear();
        db.Set<ProcessedUnit>().Add(new ProcessedUnit
        {
            TenantId = caller.TenantId, UnitId = unit.UnitId, DeviceId = caller.DeviceId,
            Outcome = UnitOutcome.Rejected, ProcessedAt = Now,
        });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (Exception e) when (errors.Classify(e) == DbErrorKind.Unique)
        {
            db.ChangeTracker.Clear();
            var done = await db.Set<ProcessedUnit>().AsNoTracking().FirstAsync(p => p.UnitId == unit.UnitId, ct);
            return new UnitResult(unit.UnitId, done.Outcome, null, []);
        }
        return new UnitResult(unit.UnitId, UnitOutcome.Rejected, reason, []);
    }
}

public static class SyncAccess
{
    /// <summary>The owner can revoke a lost phone; its still-valid access token must stop syncing.</summary>
    public static async Task RequireActiveDeviceAsync(IAppDb db, SyncCaller caller, CancellationToken ct)
    {
        var device = await db.Set<Device>().AsNoTracking()
            .Where(d => d.Id == caller.DeviceId).Select(d => new { d.DeletedAt }).FirstOrDefaultAsync(ct);
        if (device is null || device.DeletedAt is not null)
            throw new ApiException(403, "device_revoked", "The owner removed this device. Reinstall the app to sign in again.");
    }
}
