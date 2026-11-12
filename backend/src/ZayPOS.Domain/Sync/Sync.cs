using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Sync;

/// <summary>Idempotency: every pushed unit (one client UnitOfWork) is applied once.</summary>
public class ProcessedUnit : ITenantOwned
{
    public Guid TenantId { get; set; }
    public Guid UnitId { get; set; }
    public Guid DeviceId { get; set; }
    public UnitOutcome Outcome { get; set; }
    public DateTime ProcessedAt { get; set; }
}

/// <summary>An accepted-but-odd real-world event for the owner to review (README §3.4).</summary>
public class SyncIssue : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public SyncIssueKind Kind { get; set; }
    public string EntityTable { get; set; } = "";
    public Guid EntityId { get; set; }
    public string Detail { get; set; } = "";
    public Guid? DeviceId { get; set; }
    public DateTime? ResolvedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}
