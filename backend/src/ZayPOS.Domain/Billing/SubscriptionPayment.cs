using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Billing;

/// <summary>Manual KBZPay/WavePay transfer + screenshot on Cloudflare R2.</summary>
public class SubscriptionPayment : ITenantOwned
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public long Amount { get; set; }
    /// <summary>kbz|wave.</summary>
    public PaymentMethod Method { get; set; }
    /// <summary>1 or 12.</summary>
    public int Months { get; set; }
    /// <summary>R2 object key.</summary>
    public string? ScreenshotKey { get; set; }
    public SubscriptionStatus Status { get; set; }
    public string? ReviewedBy { get; set; }
    public DateTime? ReviewedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public byte[] Version { get; set; } = [];
}
