using System.Text.Json.Serialization;
using ZayPOS.Domain.Common;

namespace ZayPOS.Application.Sync;

// Wire shape of every synced table, both directions. Property names are the
// Dart field names (camelCase on the wire). Everything is nullable on input so
// partial rows (e.g. a serial status change) and missing fields can be told
// apart; the server validates what each table rule needs.

public abstract class SyncRow
{
    public Guid Id { get; init; }
    /// <summary>Optional on input; if present it must equal the token's tenant.</summary>
    public Guid? TenantId { get; init; }
    public DateTime? CreatedAt { get; init; }
    public DateTime? UpdatedAt { get; init; }
    public DateTime? DeletedAt { get; init; }
}

/// <summary>A last-writer-wins row. <see cref="Restore"/> = explicitly un-delete (README §3.3).</summary>
public abstract class LwwRow : SyncRow
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? Restore { get; init; }
}

public sealed class TenantRow : LwwRow
{
    public string? Name { get; init; }
    public string? TemplateId { get; init; }
    public string? Township { get; init; }
    public TenantPlan? Plan { get; init; }
    public DateTime? PlanExpiresAt { get; init; }
}

public sealed class TenantFeatureRow
{
    public Guid? TenantId { get; init; }
    public string? FeatureKey { get; init; }
    public bool? Enabled { get; init; }
    public DateTime? UpdatedAt { get; init; }
}

public sealed class DeviceRow : SyncRow
{
    public string? Code { get; init; }
    public string? Name { get; init; }
    public int? LastSeq { get; init; }
    public DateTime? LastSyncAt { get; init; }
}

public sealed class ProductRow : LwwRow
{
    public string? Name { get; init; }
    public string? Category { get; init; }
    public string? Unit { get; init; }
    public string? Barcode { get; init; }
    public long? Cost { get; init; }
    public long? Price { get; init; }
    public long? WholesalePrice { get; init; }
    public long? LowAlertMilli { get; init; }
    public int? WarrantyMonths { get; init; }
    public int? ExpiryAlertDays { get; init; }
    public int? Tint { get; init; }
    public string? Initial { get; init; }
}

public sealed class ProductVariantRow : LwwRow
{
    public Guid? ProductId { get; init; }
    public string? Size { get; init; }
    public string? Color { get; init; }
}

public sealed class ProductBatchRow : LwwRow
{
    public Guid? ProductId { get; init; }
    public string? BatchNo { get; init; }
    public DateOnly? ExpiryDate { get; init; }
}

public sealed class ProductSerialRow : SyncRow
{
    public Guid? ProductId { get; init; }
    public string? Serial { get; init; }
    public SerialStatus? Status { get; init; }
    public Guid? SaleLineId { get; init; }
}

public sealed class CustomerRow : LwwRow
{
    public string? Name { get; init; }
    public string? Phone { get; init; }
    public string? Address { get; init; }
    public long? CreditLimit { get; init; }
    public string? Note { get; init; }
}

public sealed class SaleRow : SyncRow
{
    public string? No { get; init; }
    /// <summary>Not in the Dart model; defaults to the pushing device.</summary>
    public Guid? DeviceId { get; init; }
    public PaymentMethod? Method { get; init; }
    public Guid? CustomerId { get; init; }
    public string? CustomerName { get; init; }
    /// <summary>Client value on input (checked); server-computed value on output.</summary>
    public long? Total { get; init; }
    public DateTime? VoidedAt { get; init; }
    /// <summary>Output only: server arrival time (Dart <c>Sale.syncedAt</c>).</summary>
    public DateTime? SyncedAt { get; init; }
}

public sealed class SaleLineRow : SyncRow
{
    public Guid? SaleId { get; init; }
    public Guid? ProductId { get; init; }
    public Guid? VariantId { get; init; }
    public Guid? BatchId { get; init; }
    public Guid? SerialId { get; init; }
    public string? Name { get; init; }
    public long? QtyMilli { get; init; }
    public long? Price { get; init; }
    public long? CostSnapshot { get; init; }
    /// <summary>Client value on input (checked); server-computed value on output.</summary>
    public long? LineTotal { get; init; }
}

public sealed class PaymentRow : SyncRow
{
    public Guid? SaleId { get; init; }
    public PaymentMethod? Method { get; init; }
    public long? Amount { get; init; }
    public long? Received { get; init; }
}

public sealed class StockMovementRow : SyncRow
{
    public Guid? ProductId { get; init; }
    public Guid? VariantId { get; init; }
    public Guid? BatchId { get; init; }
    public StockMovementType? Type { get; init; }
    public long? QtyMilli { get; init; }
    public Guid? SaleId { get; init; }
    public string? Note { get; init; }
    /// <summary>Defaults to the pushing device.</summary>
    public Guid? DeviceId { get; init; }
}

public sealed class DebtEntryRow : SyncRow
{
    public Guid? CustomerId { get; init; }
    public DebtEntryType? Type { get; init; }
    public long? Amount { get; init; }
    public Guid? SaleId { get; init; }
    public string? SaleNo { get; init; }
    public PaymentMethod? Method { get; init; }
    public string? Note { get; init; }
    /// <summary>Defaults to the pushing device.</summary>
    public Guid? DeviceId { get; init; }
}

public sealed class SyncIssueRow : SyncRow
{
    public SyncIssueKind? Kind { get; init; }
    public string? EntityTable { get; init; }
    public Guid? EntityId { get; init; }
    public string? Detail { get; init; }
    public Guid? DeviceId { get; init; }
    public DateTime? ResolvedAt { get; init; }
}

/// <summary>The "rows" object of one pushed unit.</summary>
public sealed class UnitRows
{
    public List<TenantRow>? Tenants { get; init; }
    public List<TenantFeatureRow>? TenantFeatures { get; init; }
    public List<DeviceRow>? Devices { get; init; }
    public List<ProductRow>? Products { get; init; }
    public List<ProductVariantRow>? ProductVariants { get; init; }
    public List<ProductBatchRow>? ProductBatches { get; init; }
    public List<ProductSerialRow>? ProductSerials { get; init; }
    public List<CustomerRow>? Customers { get; init; }
    public List<SaleRow>? Sales { get; init; }
    public List<SaleLineRow>? SaleLines { get; init; }
    public List<PaymentRow>? Payments { get; init; }
    public List<StockMovementRow>? StockMovements { get; init; }
    public List<DebtEntryRow>? DebtEntries { get; init; }
}

/// <summary>Pull page: every synced table, rows ordered by rowversion.</summary>
public sealed class PullChanges
{
    public List<TenantRow> Tenants { get; init; } = [];
    public List<TenantFeatureRow> TenantFeatures { get; init; } = [];
    public List<DeviceRow> Devices { get; init; } = [];
    public List<ProductRow> Products { get; init; } = [];
    public List<ProductVariantRow> ProductVariants { get; init; } = [];
    public List<ProductBatchRow> ProductBatches { get; init; } = [];
    public List<ProductSerialRow> ProductSerials { get; init; } = [];
    public List<CustomerRow> Customers { get; init; } = [];
    public List<SaleRow> Sales { get; init; } = [];
    public List<SaleLineRow> SaleLines { get; init; } = [];
    public List<PaymentRow> Payments { get; init; } = [];
    public List<StockMovementRow> StockMovements { get; init; } = [];
    public List<DebtEntryRow> DebtEntries { get; init; } = [];
    public List<SyncIssueRow> SyncIssues { get; init; } = [];
}
