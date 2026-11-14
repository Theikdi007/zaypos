using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 5 — server half of owner decision 3 (trade-in, f5b6e3b): "an IMEI whose last status is 'sold' can be received
/// again (new inStock row, history kept); an IMEI that is 'inStock' is still refused". README §3.4 duplicateSerial: "a new
/// live in-stock IMEI whose serial another live in-stock row already has" is flagged. Rows in the wire shape of
/// mobile/lib/core/sync/wire.dart (round-5 Drift record: a voidSale unit carries the sold row back with status inStock).
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound5Tests(SqlServerFixture sql)
{
    private const string Imei = "355555555555551";

    private static object SerialRow(Guid id, Guid product, string status, Guid? saleLineId = null)
    {
        var t = Now();
        return new { id, productId = product, serial = Imei, status, saleLineId, createdAt = t, updatedAt = t };
    }

    private static object Move(Guid product, long qtyMilli, string type, Guid? saleId = null)
    {
        var t = Now();
        return new { id = Guid.CreateVersion7(), productId = product, type, qtyMilli, saleId, createdAt = t, updatedAt = t };
    }

    /// <summary>A cash checkout of one IMEI row (line carries serialId, the row becomes sold with its line).</summary>
    private static (object Unit, Guid SaleId, Guid LineId) SellImei(Guid product, Guid serialRow, string no)
    {
        var t = Now();
        Guid saleId = Guid.CreateVersion7(), lineId = Guid.CreateVersion7();
        return (Unit("checkout", new
        {
            sales = new[] { new { id = saleId, no, method = "cash", total = 450000L, createdAt = t, updatedAt = t } },
            saleLines = new[]
            {
                new { id = lineId, saleId, productId = product, serialId = serialRow, name = "phone", qtyMilli = 1000L,
                      price = 450000L, costSnapshot = 400000L, lineTotal = 450000L, createdAt = t, updatedAt = t },
            },
            payments = new[] { new { id = Guid.CreateVersion7(), saleId, method = "cash", amount = 450000L, received = 450000L, createdAt = t, updatedAt = t } },
            stockMovements = new[] { Move(product, -1000, "sale", saleId) },
            productSerials = new[] { SerialRow(serialRow, product, "sold", lineId) },
        }), saleId, lineId);
    }

    private static object TradeIn(Guid product, Guid newRow) => Unit("restock", new
    {
        productSerials = new[] { SerialRow(newRow, product, "inStock") },
        stockMovements = new[] { Move(product, 1000, "restock") },
    });

    private async Task<(QaShop A, QaShop B, Guid Product, Guid OldRow, Guid Sale1, Guid Line1)> SoldPhone()
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var product = await AddProduct(a, 0, "QA R5 trade-in");
        var oldRow = Guid.CreateVersion7();
        (await PushOne(a, Unit("restock", new
        {
            productSerials = new[] { SerialRow(oldRow, product, "inStock") },
            stockMovements = new[] { Move(product, 1000, "restock") },
        }))).Outcome.Should().Be(UnitOutcome.Applied);
        var (sale, saleId, lineId) = SellImei(product, oldRow, "A-0001");
        var r = await PushOne(a, sale);
        r.Outcome.Should().Be(UnitOutcome.Applied);
        r.Issues.Should().BeEmpty();
        return (a, b, product, oldRow, saleId, lineId);
    }

    // TC-SYNC-NEW-10 (decision 3, server): phone B takes the sold IMEI back (trade-in) → applied, no issue; phone A sells
    // the NEW row → applied, no serialDoubleSold (different row); the old row keeps its first sale line; stock 0.
    [Fact]
    public async Task TC_SYNC_NEW_10_trade_in_on_phone_B_then_sold_again_on_A_raises_no_issue_and_keeps_history()
    {
        var (a, b, product, oldRow, _, line1) = await SoldPhone();
        var newRow = Guid.CreateVersion7();
        var back = await PushOne(b, TradeIn(product, newRow));
        back.Outcome.Should().Be(UnitOutcome.Applied);
        back.Issues.Should().BeEmpty("the only other row with the IMEI is sold");

        var (sale2, _, line2) = SellImei(product, newRow, "A-0002");
        var r2 = await PushOne(a, sale2);
        r2.Outcome.Should().Be(UnitOutcome.Applied);
        r2.Issues.Should().BeEmpty("a different row is sold: no serialDoubleSold");

        await using var db = sql.CreateContext(a.TenantId);
        var rows = await db.ProductSerials.Where(s => s.Serial == Imei).ToDictionaryAsync(s => s.Id);
        rows.Should().HaveCount(2);
        (rows[oldRow].Status, rows[oldRow].SaleLineId).Should().Be((SerialStatus.Sold, line1), "history kept");
        (rows[newRow].Status, rows[newRow].SaleLineId).Should().Be((SerialStatus.Sold, line2));
        (await db.StockMovements.Where(m => m.ProductId == product).SumAsync(m => m.QtyMilli)).Should().Be(0);
        (await db.SyncIssues.CountAsync()).Should().Be(0);
    }

    // TC-SYNC-NEW-9 (new, BUG-23 server half): after the trade-in (new row in stock), the ORIGINAL sale is voided — the
    // app's voidSale unit puts the old row back to inStock. Expected (decision 3 "an in-stock IMEI is never duplicated",
    // README §3.4 duplicateSerial): the unit is applied (never rejected) and the owner is told: a duplicateSerial issue.
    [Fact]
    public async Task TC_SYNC_NEW_9_void_of_the_original_sale_after_a_trade_in_puts_the_imei_in_stock_twice_and_is_flagged()
    {
        var (a, b, product, oldRow, sale1, _) = await SoldPhone();
        (await PushOne(b, TradeIn(product, Guid.CreateVersion7()))).Issues.Should().BeEmpty();

        var t = Now();
        var v = await PushOne(a, Unit("voidSale", new
        {
            sales = new[] { new { id = sale1, voidedAt = t, updatedAt = t } },
            stockMovements = new[] { Move(product, 1000, "voidReturn", sale1) },
            productSerials = new[] { SerialRow(oldRow, product, "inStock") },
        }));
        v.Outcome.Should().Be(UnitOutcome.Applied, "never rejected");

        await using var db = sql.CreateContext(a.TenantId);
        var inStock = await db.ProductSerials.CountAsync(s => s.Serial == Imei && s.Status == SerialStatus.InStock && s.DeletedAt == null);
        var stock = await db.StockMovements.Where(m => m.ProductId == product).SumAsync(m => m.QtyMilli);
        v.Issues.Should().Contain(SyncIssueKind.DuplicateSerial,
            $"the IMEI is now in stock twice (in-stock rows: {inStock}, stock: {stock}); the owner must see it in \"စစ်ရန်\"");
    }
}
