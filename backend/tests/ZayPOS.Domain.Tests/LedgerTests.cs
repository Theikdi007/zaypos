using FluentAssertions;
using ZayPOS.Domain.Common;

namespace ZayPOS.Domain.Tests;

public class LedgerTests
{
    [Theory]
    [InlineData(1500, 1000, 1500)]   // 1 × 1500
    [InlineData(1500, 2500, 3750)]   // 2.5 × 1500
    [InlineData(333, 1500, 500)]     // 499.5 → 500 (half away from zero)
    [InlineData(-333, 1500, -500)]   // symmetric for negatives
    [InlineData(1, 499, 0)]
    [InlineData(1, 500, 1)]
    public void LineTotal_matches_dart_Qty_lineTotal(long price, long qtyMilli, long expected) =>
        Ledger.LineTotal(price, qtyMilli).Should().Be(expected);

    [Theory]
    [InlineData(DebtEntryType.CreditSale, 5000, 5000)]
    [InlineData(DebtEntryType.Payment, 2000, -2000)]
    [InlineData(DebtEntryType.Adjustment, -5000, -5000)]
    public void DebtEffect_matches_dart_DebtEntry_effect(DebtEntryType type, long amount, long expected) =>
        Ledger.DebtEffect(type, amount).Should().Be(expected);
}
