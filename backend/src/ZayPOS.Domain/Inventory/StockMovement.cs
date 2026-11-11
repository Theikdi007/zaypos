using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Inventory;

/// <summary>Dart <c>StockMovement</c>. Append-only ledger: stock on hand = SUM(QtyMilli).</summary>
public class StockMovement : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid ProductId { get; set; }
    public Guid? VariantId { get; set; }
    public Guid? BatchId { get; set; }
    public StockMovementType Type { get; set; }
    /// <summary>Signed: + in, - out.</summary>
    public long QtyMilli { get; set; }
    public Guid? SaleId { get; set; }
    public string Note { get; set; } = "";
    public Guid? DeviceId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}
