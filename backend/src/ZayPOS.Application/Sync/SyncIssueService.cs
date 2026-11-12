using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Sync;

namespace ZayPOS.Application.Sync;

/// <summary>
/// POST /sync/issues/{id}/resolve: the owner marks a sync issue as reviewed. Sets ResolvedAt and
/// UpdatedAt (so every phone pulls the change). Idempotent: resolving again keeps the first time.
/// Tenant scope = global query filter, so another shop's issue is simply not found.
/// </summary>
public sealed class SyncIssueService(IAppDb db, TimeProvider clock)
{
    public async Task<SyncIssueRow> ResolveAsync(Guid id, CancellationToken ct)
    {
        var issue = await db.Set<SyncIssue>().FirstOrDefaultAsync(i => i.Id == id && i.DeletedAt == null, ct)
                    ?? throw new ApiException(404, "not_found", "No such sync issue in this shop.");
        if (issue.ResolvedAt is null)
        {
            var now = SyncJson.ToUtcMs(clock.GetUtcNow().UtcDateTime);
            issue.ResolvedAt = now;
            issue.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
        }
        return issue.ToRow();
    }
}
