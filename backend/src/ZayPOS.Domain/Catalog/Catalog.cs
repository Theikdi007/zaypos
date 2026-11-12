using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Catalog;

/// <summary>Dart <c>Product</c>. Stock is NOT stored: it is the sum of StockMovements.</summary>
public class Product : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public string Unit { get; set; } = "";
    public string? Barcode { get; set; }
    public long Cost { get; set; }
    public long Price { get; set; }
    public long? WholesalePrice { get; set; }
    public long LowAlertMilli { get; set; }
    public int? WarrantyMonths { get; set; }
    public int? ExpiryAlertDays { get; set; }
    /// <summary>ARGB tile color (UI).</summary>
    public int Tint { get; set; }
    /// <summary>Tile letter (UI).</summary>
    public string Initial { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Dart <c>ProductVariant</c> (size × color).</summary>
public class ProductVariant : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid ProductId { get; set; }
    public string Size { get; set; } = "";
    public string Color { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Dart <c>ProductBatch</c>. Batch qty is derived (sum of movements with this BatchId).</summary>
public class ProductBatch : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid ProductId { get; set; }
    public string BatchNo { get; set; } = "";
    public DateOnly? ExpiryDate { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Dart <c>ProductSerial</c> (IMEI / serial).</summary>
public class ProductSerial : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid ProductId { get; set; }
    public string Serial { get; set; } = "";
    public SerialStatus Status { get; set; }
    public Guid? SaleLineId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Global (not per tenant) starter catalog per shop template.</summary>
public class PresetProduct
{
    public Guid Id { get; set; }
    public string TemplateId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public string Unit { get; set; } = "";
    public string? Barcode { get; set; }
    public long? SuggestedPrice { get; set; }
    public int SortOrder { get; set; }
    public DateTime UpdatedAt { get; set; }
}
