using System.Text.Json;
using ZayPOS.Domain.Common;

namespace ZayPOS.Application.Sync;

/// <summary>Who is syncing, from the access token (never from the body).</summary>
public sealed record SyncCaller(Guid TenantId, Guid UserId, Guid DeviceId);

public sealed record PushRequest(Guid DeviceId, List<PushUnit>? Units);

/// <summary>
/// One client UnitOfWork. <see cref="Rows"/> stays raw JSON until the unit is processed,
/// so one malformed unit is <c>rejected</c> without failing the whole batch.
/// </summary>
public sealed record PushUnit(Guid UnitId, string? Kind, DateTime? ClientTime, JsonElement Rows);

public sealed record PushResponse(IReadOnlyList<UnitResult> Results, DateTime ServerTime);

public sealed record UnitResult(Guid UnitId, UnitOutcome Outcome, string? Reason, IReadOnlyList<SyncIssueKind> Issues);

public sealed record PullResponse(PullChanges Changes, string Cursor, bool HasMore);

public interface ISyncPull
{
    Task<PullResponse> PullAsync(byte[] cursor, int limit, CancellationToken ct);
}

public static class UnitKinds
{
    public const string Checkout = "checkout";
    public const string VoidSale = "voidSale";
    public const string PayDebt = "payDebt";
    public const string UpsertProduct = "upsertProduct";
    public const string UpsertCustomer = "upsertCustomer";
    public const string SetFeatures = "setFeatures";
    public const string StockAdjust = "stockAdjust";
    public const string Restock = "restock";

    public static readonly IReadOnlySet<string> All = new HashSet<string>(StringComparer.Ordinal)
    {
        Checkout, VoidSale, PayDebt, UpsertProduct, UpsertCustomer, SetFeatures, StockAdjust, Restock,
    };
}

/// <summary>A shape/reference problem: the unit is <c>rejected</c> (README §3.1 step 2; only bugs get here).</summary>
public sealed class SyncRejectException(string reason) : Exception(reason);

/// <summary>Pull cursor = 8-byte rowversion as 16 hex chars. "0" or empty = from the start.</summary>
public static class SyncCursor
{
    public static byte[] Parse(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) return new byte[8];
        var s = hex.Trim();
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s[2..];
        if (s.Length > 16 || !s.All(Uri.IsHexDigit))
            throw new Abstractions.ApiException(400, "validation", "cursor must be up to 16 hex digits.");
        return Convert.FromHexString(s.PadLeft(16, '0'));
    }

    public static string Format(byte[] version) => Convert.ToHexString(version);

    /// <summary>rowversion order = unsigned big-endian = byte-wise.</summary>
    public static int Compare(byte[] a, byte[] b) => a.AsSpan().SequenceCompareTo(b);
}
