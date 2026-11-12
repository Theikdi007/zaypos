using System.Reflection;

namespace ZayPOS.Application.Sync;

/// <summary>What a text field accepts besides its length.</summary>
public enum NonAsciiRule
{
    /// <summary>nvarchar: any text.</summary>
    Allow,
    /// <summary>varchar: non-ASCII is rejected (SQL Server would silently mangle it).</summary>
    Reject,
    /// <summary>varchar: non-ASCII characters are dropped (e.g. phone formatting).</summary>
    Drop,
}

/// <summary>
/// One text field of a pushed row. <see cref="Field"/> is the wire name used in reject reasons
/// ("products.name"). <see cref="MaxLength"/> counts UTF-16 code units (= SQL Server nvarchar length).
/// </summary>
public sealed record TextLimit(
    string Field,
    int MaxLength,
    bool Required = true,
    bool AllowEmpty = false,
    bool MyanmarDigitsToAscii = false,
    NonAsciiRule NonAscii = NonAsciiRule.Allow)
{
    /// <summary>Validates and normalizes <paramref name="value"/>; null stays null for optional fields.</summary>
    public string? Apply(string? value)
    {
        if (value is null)
            return Required ? throw new SyncRejectException($"{Field} is required.") : null;
        if (value.Length == 0 && Required && !AllowEmpty) throw new SyncRejectException($"{Field} must not be empty.");
        if (value.Length > MaxLength) throw new SyncRejectException($"{Field} is longer than {MaxLength} characters.");

        if (MyanmarDigitsToAscii) value = SyncText.AsciiDigits(value);
        return NonAscii switch
        {
            NonAsciiRule.Reject when !value.All(char.IsAscii) =>
                throw new SyncRejectException($"{Field} must be ASCII (digits/latin letters)."),
            NonAsciiRule.Drop => new string(value.Where(char.IsAscii).ToArray()),
            _ => value,
        };
    }
}

/// <summary>One integer field of a pushed row: <see cref="Min"/> ≤ value ≤ <see cref="Max"/> (null = no bound).</summary>
public sealed record NumberLimit(string Field, long? Min = null, long? Max = null, string? Note = null)
{
    public long Apply(long value)
    {
        if (Min is { } min && value < min) throw new SyncRejectException($"{Field} must be >= {min}.");
        if (Max is { } max && value > max) throw new SyncRejectException($"{Field} must be <= {max}.");
        return value;
    }
}

/// <summary>
/// Every limit the sync validator enforces, in one place. The applier reads these (never literals),
/// and GET /api/v1/sync/limits publishes them so the app can enforce the same rules before saving.
/// Text lengths must fit the database columns (guarded by a schema test).
/// </summary>
public static class SyncLimits
{
    // ------------------------------------------------------------ request / protocol
    public const int MaxUnitsPerPush = 50;
    public const int PullDefaultLimit = 500;
    public const int PullMaxLimit = 1000;
    /// <summary>Edit times later than server time + this are clamped (and raise clockSkew).</summary>
    public static readonly TimeSpan MaxClockAhead = TimeSpan.FromMinutes(5);
    /// <summary>SyncIssues.Detail (server-written, truncated).</summary>
    public const int IssueDetailMaxLength = 400;

    // ------------------------------------------------------------ text
    public static readonly TextLimit TenantName = new("tenants.name", 120);
    public static readonly TextLimit TenantTownship = new("tenants.township", 80, Required: false);
    public static readonly TextLimit FeatureKey = new("tenantFeatures.featureKey", 40, NonAscii: NonAsciiRule.Reject);
    public static readonly TextLimit ProductName = new("products.name", 150);
    public static readonly TextLimit ProductCategory = new("products.category", 60);
    public static readonly TextLimit ProductUnit = new("products.unit", 20, AllowEmpty: true);
    public static readonly TextLimit ProductBarcode = new("products.barcode", 64, Required: false, MyanmarDigitsToAscii: true, NonAscii: NonAsciiRule.Reject);
    public static readonly TextLimit ProductInitial = new("products.initial", 4, AllowEmpty: true);
    public static readonly TextLimit VariantSize = new("productVariants.size", 20, AllowEmpty: true);
    public static readonly TextLimit VariantColor = new("productVariants.color", 30, AllowEmpty: true);
    public static readonly TextLimit BatchNo = new("productBatches.batchNo", 40, AllowEmpty: true);
    public static readonly TextLimit Serial = new("productSerials.serial", 40, MyanmarDigitsToAscii: true, NonAscii: NonAsciiRule.Reject);
    public static readonly TextLimit CustomerName = new("customers.name", 100);
    public static readonly TextLimit CustomerPhone = new("customers.phone", 20, Required: false, MyanmarDigitsToAscii: true, NonAscii: NonAsciiRule.Drop);
    public static readonly TextLimit CustomerAddress = new("customers.address", 200, Required: false);
    public static readonly TextLimit CustomerNote = new("customers.note", 300, Required: false);
    public static readonly TextLimit SaleNo = new("sales.no", 12, NonAscii: NonAsciiRule.Reject);
    public static readonly TextLimit SaleCustomerName = new("sales.customerName", 100, Required: false);
    public static readonly TextLimit SaleLineName = new("saleLines.name", 150);
    public static readonly TextLimit StockMovementNote = new("stockMovements.note", 200, Required: false);
    public static readonly TextLimit DebtEntrySaleNo = new("debtEntries.saleNo", 12, Required: false, NonAscii: NonAsciiRule.Reject);
    public static readonly TextLimit DebtEntryNote = new("debtEntries.note", 200, Required: false);

    // ------------------------------------------------------------ numbers (money = kyats, qty = milli-units)
    public static readonly NumberLimit ProductCost = new("products.cost", Min: 0);
    public static readonly NumberLimit ProductPrice = new("products.price", Min: 0);
    public static readonly NumberLimit ProductWholesalePrice = new("products.wholesalePrice", Min: 0);
    public static readonly NumberLimit CustomerCreditLimit = new("customers.creditLimit", Min: 0);
    public static readonly NumberLimit DeviceLastSeq = new("devices.lastSeq", Min: 0, Max: int.MaxValue);
    public static readonly NumberLimit SaleLineQty = new("saleLines.qtyMilli", Min: 1);
    public static readonly NumberLimit SaleLinePrice = new("saleLines.price", Min: 0);
    public static readonly NumberLimit SaleLineCost = new("saleLines.costSnapshot", Min: 0);
    public static readonly NumberLimit PaymentAmount = new("payments.amount", Min: 0, Note: "received, when set, must be >= amount");
    public static readonly NumberLimit DebtEntryAmount = new("debtEntries.amount", Min: 1, Note: "creditSale and payment only; adjustment may be any sign");

    public static IReadOnlyList<TextLimit> Texts { get; } = FieldsOf<TextLimit>();
    public static IReadOnlyList<NumberLimit> Numbers { get; } = FieldsOf<NumberLimit>();

    /// <summary>The published shape (GET /sync/limits).</summary>
    public static SyncLimitsResponse Describe() => new(
        MaxUnitsPerPush, PullDefaultLimit, PullMaxLimit, (int)MaxClockAhead.TotalSeconds,
        Texts.ToDictionary(t => t.Field, t => new TextLimitDto(t.MaxLength, t.Required, t.AllowEmpty, t.MyanmarDigitsToAscii, t.NonAscii)),
        Numbers.ToDictionary(n => n.Field, n => new NumberLimitDto(n.Min, n.Max, n.Note)));

    private static List<T> FieldsOf<T>() =>
        typeof(SyncLimits).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(f => f.FieldType == typeof(T))
            .Select(f => (T)f.GetValue(null)!)
            .ToList();
}

public sealed record SyncLimitsResponse(
    int MaxUnitsPerPush,
    int PullDefaultLimit,
    int PullMaxLimit,
    int MaxClockAheadSeconds,
    IReadOnlyDictionary<string, TextLimitDto> Text,
    IReadOnlyDictionary<string, NumberLimitDto> Numbers);

public sealed record TextLimitDto(int MaxLength, bool Required, bool AllowEmpty, bool MyanmarDigitsToAscii, NonAsciiRule NonAscii);

public sealed record NumberLimitDto(long? Min, long? Max, string? Note);

public static class SyncText
{
    /// <summary>Myanmar digits ၀-၉ (U+1040–U+1049) → 0-9.</summary>
    public static string AsciiDigits(string value) =>
        string.Create(value.Length, value, (span, v) =>
        {
            for (var i = 0; i < v.Length; i++)
                span[i] = v[i] is >= '၀' and <= '၉' ? (char)('0' + (v[i] - '၀')) : v[i];
        });
}
