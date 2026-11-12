using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Customers;

/// <summary>Dart <c>Customer</c>. Balance is NOT stored: it is the sum of DebtEntry effects.</summary>
public class Customer : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Name { get; set; } = "";
    public string Phone { get; set; } = "";
    public string? Address { get; set; }
    public long? CreditLimit { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Dart <c>DebtEntry</c>. Append-only ledger; sign rules in <see cref="Ledger.DebtEffect"/>.</summary>
public class DebtEntry : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid CustomerId { get; set; }
    public DebtEntryType Type { get; set; }
    public long Amount { get; set; }
    public Guid? SaleId { get; set; }
    /// <summary>Receipt number snapshot.</summary>
    public string? SaleNo { get; set; }
    /// <summary>For payments: cash|kbz|wave.</summary>
    public PaymentMethod? Method { get; set; }
    public string? Note { get; set; }
    public Guid? DeviceId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];

    public long Effect => Ledger.DebtEffect(Type, Amount);
}
