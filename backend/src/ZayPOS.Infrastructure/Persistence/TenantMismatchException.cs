namespace ZayPOS.Infrastructure.Persistence;

/// <summary>A row for another tenant was about to be written. Always a bug, never user input.</summary>
public sealed class TenantMismatchException(string entity, Guid rowTenantId, Guid currentTenantId)
    : InvalidOperationException(
        $"Refusing to save {entity} for tenant {rowTenantId}: the current tenant is {currentTenantId}.")
{
    public Guid RowTenantId { get; } = rowTenantId;
    public Guid CurrentTenantId { get; } = currentTenantId;
}
