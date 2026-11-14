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

/// <summary>
/// <see cref="Reason"/> = English (logs, old apps). Apps show their own message from <see cref="Code"/> +
/// <see cref="Data"/> (see <see cref="RejectCodes"/>); both null except for a fresh rejection.
/// </summary>
public sealed record UnitResult(Guid UnitId, UnitOutcome Outcome, string? Reason, IReadOnlyList<SyncIssueKind> Issues,
    string? Code = null, IReadOnlyDictionary<string, string>? Data = null);

/// <summary>SyncIssues.Data: the issue's structured fields as a camelCase JSON object that always fits the column.</summary>
public static class SyncIssueData
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>If it would not fit, long texts are cut and name lists keep one name (othersCount stays exact).</summary>
    public static string Serialize(Dictionary<string, object?> data)
    {
        var json = JsonSerializer.Serialize(data, Json);
        if (json.Length <= SyncLimits.IssueDataMaxLength) return json;
        var cut = data.ToDictionary(kv => kv.Key, kv => kv.Value switch
        {
            string s when s.Length > 100 => s[..100],
            IEnumerable<string> names => names.Take(1).Select(n => n.Length > 100 ? n[..100] : n).ToList(),
            var v => v,
        });
        return JsonSerializer.Serialize(cut, Json);
    }
}

/// <summary>Stable codes of a rejected unit. Data keys: field (wire "table.column"), min, max, kind.</summary>
public static class RejectCodes
{
    public const string FieldRequired = "fieldRequired";
    public const string FieldEmpty = "fieldEmpty";
    public const string FieldTooLong = "fieldTooLong";
    public const string FieldNotAscii = "fieldNotAscii";
    public const string FieldTooSmall = "fieldTooSmall";
    public const string FieldTooLarge = "fieldTooLarge";
    public const string UnknownKind = "unknownKind";
    public const string NotFound = "notFound";
    public const string DatabaseRefused = "databaseRefused";
    /// <summary>Any other shape problem (only app bugs get here).</summary>
    public const string Invalid = "invalid";
}

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
public sealed class SyncRejectException(string reason, string code = RejectCodes.Invalid,
    IReadOnlyDictionary<string, string>? data = null) : Exception(reason)
{
    public string Code { get; } = code;
    public IReadOnlyDictionary<string, string>? Fields { get; } = data;
}

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
