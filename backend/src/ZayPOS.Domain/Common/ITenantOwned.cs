namespace ZayPOS.Domain.Common;

/// <summary>A row that belongs to one shop. Gets the TenantId global query filter.</summary>
public interface ITenantOwned
{
    Guid TenantId { get; }
}

/// <summary>A row with a rowversion: the sync pull cursor.</summary>
public interface IVersioned
{
    byte[] Version { get; }
}

/// <summary>
/// A synced row: client-generated Id, UTC timestamps, soft delete and the
/// rowversion pull cursor.
/// </summary>
public interface ISyncedRow : ITenantOwned, IVersioned
{
    Guid Id { get; set; }
    new Guid TenantId { get; set; }
    DateTime CreatedAt { get; set; }
    DateTime UpdatedAt { get; set; }
    DateTime? DeletedAt { get; set; }
}
