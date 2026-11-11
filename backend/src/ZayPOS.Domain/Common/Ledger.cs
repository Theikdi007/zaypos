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

    /// <summary>Signed effect of a debt entry on the customer balance. Same as Dart <c>DebtEntry.effect</c>.</summary>
    public static long DebtEffect(DebtEntryType type, long amount) => type switch
    {
        DebtEntryType.CreditSale => amount,
        DebtEntryType.Payment => -amount,
        DebtEntryType.Adjustment => amount,
        _ => throw new ArgumentOutOfRangeException(nameof(type), type, null),
    };
}
