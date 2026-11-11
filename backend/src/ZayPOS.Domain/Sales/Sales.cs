using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Sales;

/// <summary>Dart <c>Sale</c>. <c>ReceivedAt</c> is Dart <c>syncedAt</c>; <c>Total</c> is recomputed by the server.</summary>
public class Sale : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    /// <summary>Receipt number, "A-1033".</summary>
    public string No { get; set; } = "";
    public Guid DeviceId { get; set; }
    public PaymentMethod Method { get; set; }
    /// <summary>Required when Method = debt.</summary>
    public Guid? CustomerId { get; set; }
    public string? CustomerName { get; set; }
    public long Total { get; set; }
    public DateTime? VoidedAt { get; set; }
    /// <summary>Sale time on the device (UTC).</summary>
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    /// <summary>Server arrival time (DB default SYSUTCDATETIME()).</summary>
    public DateTime ReceivedAt { get; set; }
    public byte[] Version { get; set; } = [];

    public List<SaleLine> Lines { get; set; } = [];
    public List<Payment> Payments { get; set; } = [];
}

/// <summary>Dart <c>SaleLine</c>. ProductId NULL = Quick Sale line.</summary>
public class SaleLine : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid SaleId { get; set; }
    public Guid? ProductId { get; set; }
    public Guid? VariantId { get; set; }
    public Guid? BatchId { get; set; }
    public Guid? SerialId { get; set; }
    public string Name { get; set; } = "";
    public long QtyMilli { get; set; }
    /// <summary>Kyats per unit.</summary>
    public long Price { get; set; }
    /// <summary>Kyats per unit at sale time.</summary>
    public long CostSnapshot { get; set; }
    /// <summary><see cref="Ledger.LineTotal"/>(Price, QtyMilli), computed by the server.</summary>
    public long LineTotal { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Dart <c>Payment</c>. Method is never debt.</summary>
public class Payment : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid SaleId { get; set; }
    public PaymentMethod Method { get; set; }
    public long Amount { get; set; }
    /// <summary>Cash handed over.</summary>
    public long? Received { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}
