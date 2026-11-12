namespace ZayPOS.Domain.Common;

/// <summary>Money and ledger math, identical to the Dart <c>Qty</c> / <c>DebtEntry.effect</c> rules.</summary>
public static class Ledger
{
    public const long QtyScale = 1000;

    /// <summary>
    /// price (kyats per unit) × qty (milli-units), rounded half away from zero
    /// to whole kyats. Same as Dart <c>Qty.lineTotal</c>.
    /// </summary>
    public static long LineTotal(long priceKyats, long qtyMilli)
    {
        var p = checked(priceKyats * qtyMilli);
        return p >= 0
            ? (p + QtyScale / 2) / QtyScale
            : -((-p + QtyScale / 2) / QtyScale);
    }

    /// <summary>2500 → "2.5", 3000 → "3", -1500 → "-1.5". Same as Dart <c>Qty.format</c>.</summary>
    public static string FormatQty(long milli)
    {
        var abs = Math.Abs(milli);
        var frac = (abs % QtyScale).ToString("D3").TrimEnd('0');
        var s = frac.Length == 0 ? $"{abs / QtyScale}" : $"{abs / QtyScale}.{frac}";
        return milli < 0 ? "-" + s : s;
    }

    /// <summary>Signed effect of a debt entry on the customer balance. Same as Dart <c>DebtEntry.effect</c>.</summary>
    public static long DebtEffect(DebtEntryType type, long amount) => type switch
    {
        DebtEntryType.CreditSale => amount,
        DebtEntryType.Payment => -amount,
        DebtEntryType.Adjustment => amount,
        _ => throw new ArgumentOutOfRangeException(nameof(type), type, null),
    };
}
