using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Account;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Billing;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Subscription;

/// <summary>Config section "Subscription": what the app shows on the pay screen. Prices are kyats.</summary>
public sealed class SubscriptionOptions
{
    public const string Section = "Subscription";
    public List<PlanPrice> Prices { get; set; } = [];
    /// <summary>Where to transfer: method ("kbz"/"wave") → account phone/number shown to the owner.</summary>
    public Dictionary<string, string> PayTo { get; set; } = [];
}

public sealed class PlanPrice
{
    public int Months { get; set; }
    public long Amount { get; set; }
}

public sealed record ScreenshotUrlRequest(string? ContentType, long SizeBytes);

public sealed record CreateSubscriptionPayment(Guid Id, PaymentMethod? Method, int Months, long Amount, string? ScreenshotKey);

public sealed record SubscriptionPaymentDto(Guid Id, long Amount, PaymentMethod Method, int Months, SubscriptionStatus Status,
    DateTime CreatedAt, DateTime? ReviewedAt);

public sealed record SubscriptionResponse(PlanInfo Plan, IReadOnlyList<PlanPrice> Prices, IReadOnlyDictionary<string, string> PayTo,
    IReadOnlyList<SubscriptionPaymentDto> Payments);

/// <summary>
/// Manual KBZPay/WavePay subscription (README §5): the owner transfers, uploads the screenshot
/// straight to object storage with a presigned PUT, then records the payment for admin review.
/// </summary>
public sealed class SubscriptionService(IAppDb db, IFileStorage storage, IOptions<SubscriptionOptions> options, TimeProvider clock)
{
    public const long MaxScreenshotBytes = 5 * 1024 * 1024;
    public const long MaxAmount = 100_000_000;
    public static readonly TimeSpan UploadUrlValidFor = TimeSpan.FromMinutes(10);
    public static readonly IReadOnlySet<int> AllowedMonths = new HashSet<int> { 1, 12 };

    private static readonly Dictionary<string, string> Extensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ["image/jpeg"] = "jpg", ["image/png"] = "png", ["image/webp"] = "webp",
    };

    private DateTime Now => SyncJson.ToUtcMs(clock.GetUtcNow().UtcDateTime);

    /// <summary>Every key of a tenant lives under this prefix; payments may only reference their own.</summary>
    public static string KeyPrefix(Guid tenantId) => $"subscriptions/{tenantId:N}/";

    public PresignedUpload ScreenshotUrl(SyncCaller caller, ScreenshotUrlRequest req)
    {
        if (req.ContentType is null || !Extensions.TryGetValue(req.ContentType, out var ext))
            throw new ApiException(400, "validation", $"contentType must be one of: {string.Join(", ", Extensions.Keys)}.");
        if (req.SizeBytes is <= 0 or > MaxScreenshotBytes)
            throw new ApiException(400, "validation", $"sizeBytes must be 1..{MaxScreenshotBytes}.");

        var key = $"{KeyPrefix(caller.TenantId)}{Guid.CreateVersion7():N}.{ext}";
        return storage.PresignUpload(key, req.ContentType.ToLowerInvariant(), req.SizeBytes, UploadUrlValidFor);
    }

    /// <summary>Idempotent by payment id (the app creates it, like every other row). One pending payment at a time.</summary>
    public async Task<(SubscriptionPaymentDto Payment, bool Created)> CreatePaymentAsync(
        SyncCaller caller, CreateSubscriptionPayment req, CancellationToken ct)
    {
        if (req.Id == Guid.Empty) throw new ApiException(400, "validation", "id is required.");
        var existing = await db.Set<SubscriptionPayment>().AsNoTracking().FirstOrDefaultAsync(p => p.Id == req.Id, ct);
        if (existing is not null) return (ToDto(existing), false);

        if (req.Method is not (PaymentMethod.Kbz or PaymentMethod.Wave))
            throw new ApiException(400, "validation", "method must be kbz or wave.");
        if (!AllowedMonths.Contains(req.Months))
            throw new ApiException(400, "validation", "months must be 1 or 12.");
        if (req.Amount is <= 0 or > MaxAmount)
            throw new ApiException(400, "validation", $"amount must be 1..{MaxAmount} kyats.");
        var key = req.ScreenshotKey;
        if (key is null || !key.StartsWith(KeyPrefix(caller.TenantId), StringComparison.Ordinal) || key.Length > 200
            || key.Contains("..") || !key.All(c => char.IsAsciiLetterOrDigit(c) || c is '/' or '.'))
            throw new ApiException(400, "validation", "screenshotKey must be a key returned by /subscription/screenshot-url.");

        if (await db.Set<SubscriptionPayment>().AnyAsync(p => p.Status == SubscriptionStatus.Pending, ct))
            throw new ApiException(409, "payment_pending", "A payment is already waiting for review.");
        if (!await storage.ExistsAsync(key, ct))
            throw new ApiException(400, "screenshot_missing", "Upload the screenshot first.");

        var now = Now;
        var payment = new SubscriptionPayment
        {
            Id = req.Id, TenantId = caller.TenantId, Amount = req.Amount, Method = req.Method.Value, Months = req.Months,
            ScreenshotKey = key, Status = SubscriptionStatus.Pending, CreatedAt = now, UpdatedAt = now,
        };
        db.Set<SubscriptionPayment>().Add(payment);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Same id pushed twice at once: the first one won.
            db.ChangeTracker.Clear();
            var winner = await db.Set<SubscriptionPayment>().AsNoTracking().FirstOrDefaultAsync(p => p.Id == req.Id, ct);
            if (winner is null) throw new ApiException(409, "conflict", "This payment id is already used.");
            return (ToDto(winner), false);
        }
        return (ToDto(payment), true);
    }

    public async Task<SubscriptionResponse> GetAsync(CancellationToken ct)
    {
        var tenant = await db.Set<Tenant>().AsNoTracking().FirstAsync(ct);
        var payments = await db.Set<SubscriptionPayment>().AsNoTracking()
            .OrderByDescending(p => p.CreatedAt).Take(20)
            .ToListAsync(ct);
        var o = options.Value;
        return new SubscriptionResponse(PlanInfo.Of(tenant, Now), o.Prices, o.PayTo, payments.Select(ToDto).ToList());
    }

    private static SubscriptionPaymentDto ToDto(SubscriptionPayment p) =>
        new(p.Id, p.Amount, p.Method, p.Months, p.Status, p.CreatedAt, p.ReviewedAt);
}
