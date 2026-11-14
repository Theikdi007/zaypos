using System.Text.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 6 — server half of BUG-22 / BUG-23 (667a0e2). Wire shapes as recorded from the app in
/// mobile/test/qa/qa_round6_drift_test.dart (TC-PROD-NEW-27 wire: product + batch {batchNo, expiryDate "yyyy-MM-dd"} +
/// two "opening batch" adjustments −loose (batchId null) / +loose (batchId = the new batch)). README §3.4 duplicateSerial:
/// "A new live in-stock ProductSerial has the same serial as another live in-stock row of the tenant"; the BUG-23 server fix
/// treats an existing row turning back to in-stock the same way.
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound6Tests(SqlServerFixture sql)
{
    private static IEnumerable<JsonElement> Rows(List<JsonElement> pages, string table) =>
        pages.SelectMany(p => p.GetProperty("changes").TryGetProperty(table, out var a) ? a.EnumerateArray() : Enumerable.Empty<JsonElement>());

    private static object Move(Guid product, long qtyMilli, string type, Guid? saleId = null, Guid? batchId = null, string? note = null)
    {
        var t = Now();
        return new { id = Guid.CreateVersion7(), productId = product, batchId, type, qtyMilli, saleId, note, createdAt = t, updatedAt = t };
    }

    private static object SerialRow(Guid id, Guid product, string imei, string status, Guid? saleLineId = null)
    {
        var t = Now();
        return new { id, productId = product, serial = imei, status, saleLineId, createdAt = t, updatedAt = t };
    }

    private static (object Unit, Guid SaleId, Guid LineId) SellImei(Guid product, Guid serialRow, string imei, string no)
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
            productSerials = new[] { SerialRow(serialRow, product, imei, "sold", lineId) },
        }), saleId, lineId);
    }

    private async Task<(QaShop A, QaShop B, Guid Product, Guid OldRow, Guid Sale1)> SoldPhone(string imei)
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var product = await AddProduct(a, 0, "QA R6 phone");
        var oldRow = Guid.CreateVersion7();
        (await PushOne(a, Unit("restock", new
        {
            productSerials = new[] { SerialRow(oldRow, product, imei, "inStock") },
            stockMovements = new[] { Move(product, 1000, "restock") },
        }))).Outcome.Should().Be(UnitOutcome.Applied);
        var (sale, saleId, _) = SellImei(product, oldRow, imei, "A-0001");
        var r = await PushOne(a, sale);
        r.Outcome.Should().Be(UnitOutcome.Applied);
        r.Issues.Should().BeEmpty();
        return (a, b, product, oldRow, saleId);
    }

    private static object TradeIn(Guid product, Guid newRow, string imei) => Unit("restock", new
    {
        productSerials = new[] { SerialRow(newRow, product, imei, "inStock") },
        stockMovements = new[] { Move(product, 1000, "restock") },
    });

    /// <summary>The voidSale unit of an app WITHOUT knowledge of the trade-in (old row back to inStock + voidReturn).</summary>
    private static object VoidReturningRow(Guid sale, Guid product, Guid oldRow, string imei)
    {
        var t = Now();
        return Unit("voidSale", new
        {
            sales = new[] { new { id = sale, voidedAt = t, updatedAt = t } },
            stockMovements = new[] { Move(product, 1000, "voidReturn", sale) },
            productSerials = new[] { SerialRow(oldRow, product, imei, "inStock") },
        });
    }

    // TC-SYNC-NEW-11 (BUG-22 server half): the edit form's upsertProduct unit — product switched to expiryAlertDays 30 +
    // new opening batch + adjustments −10 loose / +10 into the batch. Expected: applied, no issue (no negativeStock), batch
    // stock = product stock = 10, nothing outside batches; phone B pulls the product (30), the batch with its expiry and both
    // movements.
    [Fact]
    public async Task TC_SYNC_NEW_11_edit_form_opening_batch_unit_is_applied_without_issue_and_pulled_by_phone_B()
    {
        var a = await NewShop(sql.Api, "pharmacy");
        var b = await Login(sql.Api, a);
        var med = await AddProduct(a, 10_000, "QA R6 med switch");
        var cursorB = (await PullAllPages(b)).Last().GetProperty("cursor").GetString()!;

        var batch = Guid.CreateVersion7();
        var t = Now();
        var res = await PushOne(a, Unit("upsertProduct", new
        {
            products = new[]
            {
                new { id = med, name = "QA R6 med switch", category = "General", unit = "ဗူး", cost = 450L, price = 600L,
                      lowAlertMilli = 5000L, tint = 0, initial = "Q", expiryAlertDays = 30, createdAt = t, updatedAt = t },
            },
            productBatches = new[] { new { id = batch, productId = med, batchNo = "OPEN6", expiryDate = "2026-11-28", createdAt = t, updatedAt = t } },
            stockMovements = new[]
            {
                Move(med, -10_000, "adjustment", note: "opening batch"),
                Move(med, 10_000, "adjustment", batchId: batch, note: "opening batch"),
            },
        }));
        res.Outcome.Should().Be(UnitOutcome.Applied, res.Reason);
        res.Issues.Should().BeEmpty("product stock never goes below zero (−10 then +10 in one unit)");

        await using (var db = sql.CreateContext(a.TenantId))
        {
            (await db.Products.SingleAsync(p => p.Id == med)).ExpiryAlertDays.Should().Be(30);
            (await db.StockMovements.Where(m => m.ProductId == med).SumAsync(m => m.QtyMilli)).Should().Be(10_000);
            (await db.StockMovements.Where(m => m.BatchId == batch).SumAsync(m => m.QtyMilli)).Should().Be(10_000);
            (await db.StockMovements.Where(m => m.ProductId == med && m.BatchId == null).SumAsync(m => m.QtyMilli)).Should().Be(0);
            (await db.SyncIssues.CountAsync()).Should().Be(0);
        }
        var pages = await PullAllPages(b, cursorB);
        Rows(pages, "products").Single(r => r.GetProperty("id").GetGuid() == med).GetProperty("expiryAlertDays").GetInt32().Should().Be(30);
        Rows(pages, "productBatches").Single(r => r.GetProperty("id").GetGuid() == batch).GetProperty("expiryDate").GetString()
            .Should().StartWith("2026-11-28");
        Rows(pages, "stockMovements").Where(m => m.GetProperty("productId").GetGuid() == med)
            .Select(m => m.GetProperty("qtyMilli").GetInt64()).Should().BeEquivalentTo(new[] { -10_000L, 10_000L });
    }

    // TC-SYNC-NEW-12 (BUG-23, both orders + the fixed app's unit):
    // (a) A voids sale 1 offline BEFORE B's trade-in reaches the server (A's unit puts the old row back to inStock), then B
    //     pushes the trade-in → the trade-in raises duplicateSerial (the new row meets an in-stock row);
    // (b) the fixed app's void after a trade-in (sale voidedAt only, no serial row, no voidReturn for the phone) → applied,
    //     no issue, old row stays sold with its line, one in-stock row, stock 1;
    // (c) a normal void (no trade-in) → old row back in stock, NO duplicateSerial (regression of the BUG-23 server change).
    [Fact]
    public async Task TC_SYNC_NEW_12_void_and_trade_in_in_either_order_flag_two_in_stock_rows_and_a_normal_void_is_not_flagged()
    {
        // (a)
        {
            const string imei = "359000000000001";
            var (a, b, product, oldRow, sale1) = await SoldPhone(imei);
            var v = await PushOne(a, VoidReturningRow(sale1, product, oldRow, imei));
            v.Outcome.Should().Be(UnitOutcome.Applied);
            v.Issues.Should().BeEmpty("only one in-stock row yet");
            var ti = await PushOne(b, TradeIn(product, Guid.CreateVersion7(), imei));
            ti.Outcome.Should().Be(UnitOutcome.Applied, "never rejected");
            ti.Issues.Should().Contain(SyncIssueKind.DuplicateSerial, "two in-stock rows with one IMEI");
        }
        // (b)
        {
            const string imei = "359000000000002";
            var (a, b, product, oldRow, sale1) = await SoldPhone(imei);
            (await PushOne(b, TradeIn(product, Guid.CreateVersion7(), imei))).Issues.Should().BeEmpty();
            var t = Now();
            var v = await PushOne(a, Unit("voidSale", new { sales = new[] { new { id = sale1, voidedAt = t, updatedAt = t } } }));
            v.Outcome.Should().Be(UnitOutcome.Applied, v.Reason);
            v.Issues.Should().BeEmpty();
            await using var db = sql.CreateContext(a.TenantId);
            var old = await db.ProductSerials.SingleAsync(s => s.Id == oldRow);
            old.Status.Should().Be(SerialStatus.Sold, "history kept");
            (await db.ProductSerials.CountAsync(s => s.Serial == imei && s.Status == SerialStatus.InStock && s.DeletedAt == null)).Should().Be(1);
            (await db.StockMovements.Where(m => m.ProductId == product).SumAsync(m => m.QtyMilli)).Should().Be(1000);
            (await db.Sales.SingleAsync(s => s.Id == sale1)).VoidedAt.Should().NotBeNull();
        }
        // (c)
        {
            const string imei = "359000000000003";
            var (a, _, product, oldRow, sale1) = await SoldPhone(imei);
            var v = await PushOne(a, VoidReturningRow(sale1, product, oldRow, imei));
            v.Outcome.Should().Be(UnitOutcome.Applied);
            v.Issues.Should().BeEmpty("a normal void returns the only row: not a duplicate");
            await using var db = sql.CreateContext(a.TenantId);
            (await db.ProductSerials.SingleAsync(s => s.Id == oldRow)).Status.Should().Be(SerialStatus.InStock);
        }
    }
}
