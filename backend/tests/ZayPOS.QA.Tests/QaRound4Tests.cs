using System.Net;
using System.Text.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 4 — server halves of BUG-18 (duplicateSerial, 1ee4e61) and BUG-15 (the app's first count of an untracked
/// module product is now a "stockAdjust" unit carrying new module rows + "opening count" adjustments, f3a7e0f).
/// Rows in the wire shape of mobile/lib/core/sync/wire.dart.
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound4Tests(SqlServerFixture sql)
{
    private static object Serial(Guid id, Guid product, string serial, string status = "inStock", DateTime? deletedAt = null)
    {
        var t = Now();
        return new { id, productId = product, serial, status, createdAt = t, updatedAt = t, deletedAt };
    }

    private static object Move(Guid product, long qtyMilli, string type = "restock", Guid? batchId = null, Guid? variantId = null,
        string note = "")
    {
        var t = Now();
        return new { id = Guid.CreateVersion7(), productId = product, batchId, variantId, type, qtyMilli, note, createdAt = t, updatedAt = t };
    }

    private static object ReceiveImei(Guid product, Guid rowId, string imei) => Unit("restock", new
    {
        productSerials = new[] { Serial(rowId, product, imei) },
        stockMovements = new[] { Move(product, 1000) },
    });

    private static IEnumerable<JsonElement> Rows(List<JsonElement> pages, string table) =>
        pages.SelectMany(p => p.GetProperty("changes").TryGetProperty(table, out var a) ? a.EnumerateArray() : Enumerable.Empty<JsonElement>());

    // TC-SYNC-NEW-5 (BUG-18 re-test): phones A and B receive the SAME IMEI offline (own row ids). Expected (README §3.4
    // duplicateSerial): both units applied, both rows kept, ONE duplicateSerial issue on B's (the later) row; the lost-answer
    // re-push of B's unit adds no second issue; BOTH phones pull the issue; resolving it is pulled as resolved.
    [Fact]
    public async Task TC_SYNC_NEW_5_same_imei_received_on_two_phones_raises_one_duplicateSerial_that_both_phones_pull()
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var phone = await AddProduct(a, 0, "QA Dup IMEI R4");
        var cursorA = (await PullAllPages(a)).Last().GetProperty("cursor").GetString()!;
        var cursorB = (await PullAllPages(b)).Last().GetProperty("cursor").GetString()!;
        Guid rowA = Guid.CreateVersion7(), rowB = Guid.CreateVersion7();
        const string imei = "351444444444444";

        var ra = await PushOne(a, ReceiveImei(phone, rowA, imei));
        ra.Outcome.Should().Be(UnitOutcome.Applied);
        ra.Issues.Should().BeEmpty("the first phone to sync has nothing to compare with");
        var unitB = ReceiveImei(phone, rowB, imei);
        var rb = await PushOne(b, unitB);
        rb.Outcome.Should().Be(UnitOutcome.Applied, "never rejected: B's outbox must not block");
        rb.Issues.Should().Equal(SyncIssueKind.DuplicateSerial);
        (await PushOne(b, unitB)).Outcome.Should().NotBe(UnitOutcome.Rejected);

        await using (var db = sql.CreateContext(a.TenantId))
        {
            (await db.ProductSerials.CountAsync(s => s.Serial == imei && s.DeletedAt == null && s.Status == SerialStatus.InStock))
                .Should().Be(2, "both rows kept");
            (await db.StockMovements.Where(m => m.ProductId == phone).SumAsync(m => m.QtyMilli)).Should().Be(2000);
            var issues = await db.SyncIssues.Where(i => i.Kind == SyncIssueKind.DuplicateSerial).ToListAsync();
            issues.Should().ContainSingle("the re-sent unit is applied once, so no second issue");
            (issues[0].EntityTable, issues[0].EntityId).Should().Be(("ProductSerials", rowB));
        }

        Guid issueId = default;
        foreach (var (shop, cursor) in new[] { (a, cursorA), (b, cursorB) })
        {
            var pulled = Rows(await PullAllPages(shop, cursor), "syncIssues").ToList();
            var dup = pulled.Should().ContainSingle(r => r.GetProperty("kind").GetString() == "duplicateSerial").Subject;
            dup.GetProperty("entityId").GetGuid().Should().Be(rowB);
            dup.GetProperty("detail").GetString().Should().Contain(imei);
            issueId = dup.GetProperty("id").GetGuid();
        }

        var res = await a.Http.PostAsync($"/api/v1/sync/issues/{issueId}/resolve", null);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var afterB = Rows(await PullAllPages(b, cursorB), "syncIssues").Single(r => r.GetProperty("id").GetGuid() == issueId);
        afterB.TryGetProperty("resolvedAt", out var ra2).Should().BeTrue();
        ra2.ValueKind.Should().Be(JsonValueKind.String, "phone B sees it resolved");
    }

    // TC-SYNC-NEW-7: duplicateSerial is per shop. Shop X has IMEI in stock; shop Y (another tenant) receives the same
    // IMEI. Expected: no issue in Y (and nothing about X's product leaks into Y); X gets nothing either.
    [Fact]
    public async Task TC_SYNC_NEW_7_the_same_imei_in_another_shop_is_not_a_duplicate_and_leaks_nothing()
    {
        var x = await NewShop(sql.Api, "phone");
        var y = await NewShop(sql.Api, "phone");
        var px = await AddProduct(x, 0, "QA SECRET X-PRODUCT");
        var py = await AddProduct(y, 0, "QA Y product");
        const string imei = "351555555555555";
        (await PushOne(x, ReceiveImei(px, Guid.CreateVersion7(), imei))).Issues.Should().BeEmpty();
        var ry = await PushOne(y, ReceiveImei(py, Guid.CreateVersion7(), imei));
        ry.Outcome.Should().Be(UnitOutcome.Applied);
        ry.Issues.Should().BeEmpty("another shop's IMEI is not this shop's stock");

        var pulledY = Rows(await PullAllPages(y), "syncIssues").ToList();
        pulledY.Should().BeEmpty();
        await using var dbx = sql.CreateContext(x.TenantId);
        (await dbx.SyncIssues.CountAsync()).Should().Be(0);
    }

    // TC-SYNC-NEW-8 (README §3.4 wording "a NEW live in-stock row"): a new row that arrives already sold or deleted is not
    // a duplicate; two new in-stock rows with one IMEI inside ONE unit are flagged (recorded: how many issues).
    [Fact]
    public async Task TC_SYNC_NEW_8_sold_or_deleted_new_rows_are_not_flagged_two_in_one_unit_are()
    {
        var a = await NewShop(sql.Api, "phone");
        var p = await AddProduct(a, 0, "QA Dup edge R4");
        const string imei = "351666666666666";
        (await PushOne(a, ReceiveImei(p, Guid.CreateVersion7(), imei))).Issues.Should().BeEmpty();
        (await PushOne(a, Unit("upsertProduct", new { productSerials = new[] { Serial(Guid.CreateVersion7(), p, imei, "sold") } })))
            .Issues.Should().BeEmpty("a sold row is not stock");
        (await PushOne(a, Unit("upsertProduct", new
        {
            productSerials = new[] { Serial(Guid.CreateVersion7(), p, imei, deletedAt: Now()) },
        }))).Issues.Should().BeEmpty("a deleted row is not stock");

        const string twin = "351777777777777";
        var both = await PushOne(a, Unit("restock", new
        {
            productSerials = new[] { Serial(Guid.CreateVersion7(), p, twin), Serial(Guid.CreateVersion7(), p, twin) },
            stockMovements = new[] { Move(p, 2000) },
        }));
        both.Outcome.Should().Be(UnitOutcome.Applied);
        both.Issues.Should().Contain(SyncIssueKind.DuplicateSerial);
        await using var db = sql.CreateContext(a.TenantId);
        var n = await db.SyncIssues.CountAsync(i => i.Kind == SyncIssueKind.DuplicateSerial && i.Detail.Contains(twin));
        Console.WriteLine($"TC-SYNC-NEW-8 recorded: duplicateSerial issues for two twins in one unit = {n}");
        n.Should().BeGreaterThan(0);
    }

    // TC-SYNC-NEW-6 (BUG-15 server half): the app's first count of an untracked module product is now ONE "stockAdjust"
    // unit: (pharmacy) new batch + "opening count" adjustment cancelling the earlier sale + restock of the counted 20 into
    // the batch; (phone) new IMEI rows + their movement. Expected: applied, no negativeStock / other issue, product stock
    // = counted, batch stock = counted, phone B pulls the batch and the movements.
    [Fact]
    public async Task TC_SYNC_NEW_6_opening_count_stockAdjust_unit_with_new_batch_or_imeis_is_applied_and_pulled()
    {
        var a = await NewShop(sql.Api, "pharmacy");
        var b = await Login(sql.Api, a);
        var med = await AddProduct(a, 0, "QA untracked med R4");
        var (sale, _) = Checkout(a, "A-0001", med, 1000, 600);
        (await PushOne(a, sale)).Issues.Should().BeEmpty("untracked: no negativeStock (TC-SYNC-10)");
        var cursorB = (await PullAllPages(b)).Last().GetProperty("cursor").GetString()!;

        var batch = Guid.CreateVersion7();
        var t = Now();
        var res = await PushOne(a, Unit("stockAdjust", new
        {
            productBatches = new[] { new { id = batch, productId = med, batchNo = "FIRST", expiryDate = "2028-06-30", createdAt = t, updatedAt = t } },
            stockMovements = new[]
            {
                Move(med, 1000, type: "adjustment", note: "opening count"),
                Move(med, 20_000, batchId: batch),
            },
        }));
        res.Outcome.Should().Be(UnitOutcome.Applied, res.Reason);
        res.Issues.Should().BeEmpty();

        var phone = await AddProduct(a, 0, "QA untracked phone R4");
        var imeis = await PushOne(a, Unit("stockAdjust", new
        {
            productSerials = new[] { Serial(Guid.CreateVersion7(), phone, "351888888888881"), Serial(Guid.CreateVersion7(), phone, "351888888888882") },
            stockMovements = new[] { Move(phone, 2000) },
        }));
        imeis.Outcome.Should().Be(UnitOutcome.Applied, imeis.Reason);

        await using (var db = sql.CreateContext(a.TenantId))
        {
            (await db.StockMovements.Where(m => m.ProductId == med).SumAsync(m => m.QtyMilli)).Should().Be(20_000, "shows what was counted");
            (await db.StockMovements.Where(m => m.BatchId == batch).SumAsync(m => m.QtyMilli)).Should().Be(20_000);
            (await db.ProductSerials.CountAsync(s => s.ProductId == phone && s.Status == SerialStatus.InStock)).Should().Be(2);
            (await db.SyncIssues.CountAsync()).Should().Be(0);
        }
        var pages = await PullAllPages(b, cursorB);
        Rows(pages, "productBatches").Single(r => r.GetProperty("id").GetGuid() == batch).GetProperty("expiryDate").GetString()
            .Should().StartWith("2028-06-30");
        Rows(pages, "stockMovements").Where(m => m.GetProperty("productId").GetGuid() == med)
            .Sum(m => m.GetProperty("qtyMilli").GetInt64()).Should().Be(21_000, "B gets +1 opening count and +20 (the −1 sale it already had)");
    }
}
