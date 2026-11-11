using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Tenancy;

/// <summary>A shop. Dart <c>ShopSession</c> + template id.</summary>
public class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    /// <summary>Dart <c>ShopTemplate.id</c>: grocery|pharmacy|phone|fashion|hardware|service|restaurant|other.</summary>
    public string TemplateId { get; set; } = "";
    public string? Township { get; set; }
    /// <summary>Owner phone, E.164 (+959...).</summary>
    public string Phone { get; set; } = "";
    public TenantPlan Plan { get; set; } = TenantPlan.Free;
    public DateTime? PlanExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>One Dart <c>TenantFeatures</c> field as a key/value row.</summary>
public class TenantFeature : ITenantOwned
{
    public Guid TenantId { get; set; }
    /// <summary>Dart field name: quickSale, stock, presetCatalog, expiryBatch, serialWarranty, variants, decimalQty, quotation, serviceItems.</summary>
    public string FeatureKey { get; set; } = "";
    public bool Enabled { get; set; }
    public DateTime UpdatedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

public class User : ITenantOwned
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Phone { get; set; } = "";
    public string Name { get; set; } = "";
    public UserRole Role { get; set; }
    /// <summary>ASP.NET Core <c>PasswordHasher</c> output.</summary>
    public string PinHash { get; set; } = "";
    public int FailedPinCount { get; set; }
    public DateTime? LockedUntil { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>One installed app. Dart <c>Device</c>. <c>Code</c> + <c>LastSeq</c> give receipt numbers ("A-1033").</summary>
public class Device : ISyncedRow
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Code { get; set; } = "";
    public string? Name { get; set; }
    /// <summary>Highest receipt number issued by this device. Server only moves it forward.</summary>
    public int LastSeq { get; set; }
    public DateTime? LastSyncAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public byte[] Version { get; set; } = [];
}

/// <summary>Not tenant-filtered: looked up by hash before a tenant is known.</summary>
public class RefreshToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid DeviceId { get; set; }
    /// <summary>SHA-256 of the opaque token.</summary>
    public byte[] TokenHash { get; set; } = [];
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public Guid? ReplacedById { get; set; }
    public DateTime CreatedAt { get; set; }
}

/// <summary>Not tenant-filtered: exists before the tenant does (registration).</summary>
public class OtpChallenge
{
    public Guid Id { get; set; }
    public string Phone { get; set; } = "";
    public byte[] CodeHash { get; set; } = [];
    public OtpPurpose Purpose { get; set; }
    public int Attempts { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? ConsumedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}
