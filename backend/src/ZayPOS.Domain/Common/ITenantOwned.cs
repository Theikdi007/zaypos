namespace ZayPOS.Domain.Common;

/// <summary>A row that belongs to one shop. Gets the TenantId global query filter.</summary>
public interface ITenantOwned
{
    Guid TenantId { get; }
}

/// <summary>
/// A synced row: client-generated Id, UTC timestamps, soft delete and the
/// rowversion pull cursor.
/// </summary>
public interface ISyncedRow : ITenantOwned
{
    Guid Id { get; }
    DateTime CreatedAt { get; }
    DateTime UpdatedAt { get; }
    DateTime? DeletedAt { get; }
    byte[] Version { get; }
}
