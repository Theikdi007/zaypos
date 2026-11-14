using System.Text.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 3 — server halves of the BUG-12 fix: the app's new "restock" unit (StockService.receive) carries the new
/// productSerials / productBatches rows together with the movement, and the edit form's "upsertProduct" unit carries
/// new IMEIs + their +1 movements, new batches and new variants. Rows are in the wire shape of mobile/lib/core/sync/wire.dart
/// (serialWire / batchWire / variantWire, expiryDate as "yyyy-MM-dd").
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound3Tests(SqlServerFixture sql)
{
    private static object Serial(Guid id, Guid product, string serial, string status = "inStock", Guid? saleLineId = null)
    {
        var t = Now();
        return new { id, productId = product, serial, status, saleLineId, createdAt = t, updatedAt = t };
    }

    private static object Batch(Guid id, Guid product, string batchNo, string? expiryDate)
    {
        var t = Now();
        return new { id, productId = product, batchNo, expiryDate, createdAt = t, updatedAt = t };
    }

    private static object Variant(Guid id, Guid product, string size, string color)
    {
        var t = Now();
        return new { id, productId = product, size, color, createdAt = t, updatedAt = t };
    }

    private static object Restock(Guid product, long qtyMilli, Guid? batchId = null, Guid? variantId = null, string note = "")
    {
        var t = Now();
        return new { id = Guid.CreateVersion7(), productId = product, batchId, variantId, type = "restock", qtyMilli, note, createdAt = t, updatedAt = t };
    }

    private static IEnumerable<JsonElement> Rows(List<JsonElement> pages, string table) =>
        pages.SelectMany(p => p.GetProperty("changes").TryGetProperty(table, out var a) ? a.EnumerateArray() : Enumerable.Empty<JsonElement>());

    // TC-SYNC-NEW-3: phone A receives goods for an IMEI product (2 new IMEIs) and a batch product (new batch with expiry)
    // — each ONE restock unit with the new module rows + the movement. Expected: applied; pushed again (lost answer) it is
    // applied once (no second IMEI / batch / movement); phone B pulls the IMEIs (inStock), the batch (same expiry date) and
    // the movements, so B's product / batch stock equals A's; B can then sell a received IMEI (serial → sold, no issue).
    [Fact]
    public async Task TC_SYNC_NEW_3_restock_unit_with_new_imeis_and_a_new_batch_is_applied_once_and_pulled_by_phone_B()
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var phone = await AddProduct(a, 0, "QA Galaxy R3");
        var med = await AddProduct(a, 0, "QA Amoxicillin R3");
        var cursorB = (await PullAllPages(b)).Last().GetProperty("cursor").GetString()!;

        Guid s1 = Guid.CreateVersion7(), s2 = Guid.CreateVersion7(), batch = Guid.CreateVersion7();
        var imeiUnit = Unit("restock", new
        {
            productSerials = new[] { Serial(s1, phone, "356984102231001"), Serial(s2, phone, "356984102231002") },
            stockMovements = new[] { Restock(phone, 2000) },
        });
        var batchUnit = Unit("restock", new
        {
            productBatches = new[] { Batch(batch, med, "R3-B2", "2027-03-31") },
            stockMovements = new[] { Restock(med, 12_000, batchId: batch) },
        });
        var first = await Push(a, imeiUnit, batchUnit);
        first.Select(r => (r.Outcome, r.Reason)).Should().AllBeEquivalentTo((UnitOutcome.Applied, (string?)null));
        var again = await Push(a, imeiUnit, batchUnit);
        again.Select(r => r.Outcome).Should().NotContain(UnitOutcome.Rejected, "a re-sent unit must never block the outbox");

        await using (var db = sql.CreateContext(a.TenantId))
        {
            (await db.ProductSerials.CountAsync(s => s.ProductId == phone)).Should().Be(2, "applied once");
            (await db.StockMovements.Where(m => m.ProductId == phone).SumAsync(m => m.QtyMilli)).Should().Be(2000);
            var bt = await db.ProductBatches.SingleAsync(x => x.Id == batch);
            (bt.BatchNo, bt.ExpiryDate!.Value.ToString("yyyy-MM-dd")).Should().Be(("R3-B2", "2027-03-31"));
            (await db.StockMovements.Where(m => m.BatchId == batch).SumAsync(m => m.QtyMilli)).Should().Be(12_000);
        }

        var pages = await PullAllPages(b, cursorB);
        var serials = Rows(pages, "productSerials").Where(r => r.GetProperty("productId").GetGuid() == phone).ToList();
        serials.Select(r => (r.GetProperty("serial").GetString(), r.GetProperty("status").GetString()))
            .Should().BeEquivalentTo(new[] { ("356984102231001", "inStock"), ("356984102231002", "inStock") });
        var pulledBatch = Rows(pages, "productBatches").Single(r => r.GetProperty("id").GetGuid() == batch);
        pulledBatch.GetProperty("expiryDate").GetString().Should().StartWith("2027-03-31", "the phone reads it as a calendar date");
        var moves = Rows(pages, "stockMovements").ToList();
        moves.Where(m => m.GetProperty("productId").GetGuid() == phone).Sum(m => m.GetProperty("qtyMilli").GetInt64()).Should().Be(2000);
        moves.Single(m => m.TryGetProperty("batchId", out var x) && x.ValueKind == JsonValueKind.String && x.GetGuid() == batch)
            .GetProperty("qtyMilli").GetInt64().Should().Be(12_000);

        // B sells received IMEI s2 (checkout carries the serial row as "sold").
        var t = Now();
        Guid saleId = Guid.CreateVersion7(), lineId = Guid.CreateVersion7();
        var sold = await PushOne(b, Unit("checkout", new
        {
            sales = new[] { new { id = saleId, no = "B-0001", method = "cash", total = 600L, createdAt = t, updatedAt = t } },
            saleLines = new[]
            {
                new { id = lineId, saleId, productId = phone, serialId = s2, name = "QA Galaxy R3 · IMEI 356984102231002",
                      qtyMilli = 1000L, price = 600L, costSnapshot = 450L, lineTotal = 600L, createdAt = t, updatedAt = t },
            },
            payments = new[] { new { id = Guid.CreateVersion7(), saleId, method = "cash", amount = 600L, received = 600L, createdAt = t, updatedAt = t } },
            stockMovements = new[] { new { id = Guid.CreateVersion7(), productId = phone, type = "sale", qtyMilli = -1000L, saleId, createdAt = t, updatedAt = t } },
            productSerials = new[] { Serial(s2, phone, "356984102231002", "sold", lineId) },
        }));
        sold.Outcome.Should().Be(UnitOutcome.Applied, sold.Reason);
        sold.Issues.Should().BeEmpty();
        await using var db2 = sql.CreateContext(a.TenantId);
        var s = await db2.ProductSerials.SingleAsync(x => x.Id == s2);
        (s.Status, s.SaleLineId).Should().Be((SerialStatus.Sold, (Guid?)lineId));
        (await db2.ProductSerials.SingleAsync(x => x.Id == s1)).Status.Should().Be(SerialStatus.InStock);
    }

    // TC-SYNC-NEW-4: the edit form's ONE upsertProduct unit = the product row again + new IMEIs (+1 restock each, note
    // "IMEI added") + a new empty batch + a new empty variant; existing module rows are not sent. Expected: applied; the
    // existing IMEI (sold) / batch / variant rows on the server are unchanged; stock grows by the IMEI count only;
    // phone B pulls the product's new name, the new rows and the movement.
    [Fact]
    public async Task TC_SYNC_NEW_4_edit_form_unit_adds_imeis_batch_and_variant_without_touching_existing_rows()
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var p = Guid.CreateVersion7();
        var created = Now();
        Guid oldSerial = Guid.CreateVersion7(), oldBatch = Guid.CreateVersion7(), oldVariant = Guid.CreateVersion7();
        (await PushOne(a, Unit("upsertProduct", new
        {
            products = new[] { Product(p, "QA Pixel R3", updatedAt: created) },
            productSerials = new[] { Serial(oldSerial, p, "990000000000001", "sold") },
            productBatches = new[] { Batch(oldBatch, p, "OLD", "2020-01-31") },
            productVariants = new[] { Variant(oldVariant, p, "M", "အနက်") },
            stockMovements = new[] { Restock(p, 3000, batchId: oldBatch) },
        }))).Outcome.Should().Be(UnitOutcome.Applied);
        DateTime serialAt, batchAt, variantAt;
        await using (var db0 = sql.CreateContext(a.TenantId))
        {
            serialAt = (await db0.ProductSerials.SingleAsync(x => x.Id == oldSerial)).UpdatedAt;
            batchAt = (await db0.ProductBatches.SingleAsync(x => x.Id == oldBatch)).UpdatedAt;
            variantAt = (await db0.ProductVariants.SingleAsync(x => x.Id == oldVariant)).UpdatedAt;
        }
        var cursorB = (await PullAllPages(b)).Last().GetProperty("cursor").GetString()!;

        Guid n1 = Guid.CreateVersion7(), n2 = Guid.CreateVersion7(), nb = Guid.CreateVersion7(), nv = Guid.CreateVersion7();
        var edited = new
        {
            id = p, name = "QA Pixel R3 (ပြင်)", category = "General", unit = "ဗူး", cost = 450L, price = 900L, lowAlertMilli = 0,
            tint = 0, initial = "Q", createdAt = created, updatedAt = Now().AddSeconds(1),
        };
        var res = await PushOne(a, Unit("upsertProduct", new
        {
            products = new[] { edited },
            productVariants = new[] { Variant(nv, p, "XL", "အနီ") },
            productBatches = new[] { Batch(nb, p, "NEW", "2028-02-29") },
            productSerials = new[] { Serial(n1, p, "990000000000002"), Serial(n2, p, "990000000000003") },
            stockMovements = new[] { Restock(p, 2000, note: "IMEI added") },
        }));
        res.Outcome.Should().Be(UnitOutcome.Applied, res.Reason);

        await using (var db = sql.CreateContext(a.TenantId))
        {
            var prod = await db.Products.SingleAsync(x => x.Id == p);
            (prod.Name, prod.Price, prod.LowAlertMilli).Should().Be(("QA Pixel R3 (ပြင်)", 900L, 0L), "cleared low alert = 0 accepted");
            var os = await db.ProductSerials.SingleAsync(x => x.Id == oldSerial);
            (os.Status, os.UpdatedAt, os.DeletedAt).Should().Be((SerialStatus.Sold, serialAt, (DateTime?)null));
            var ob = await db.ProductBatches.SingleAsync(x => x.Id == oldBatch);
            (ob.UpdatedAt, ob.DeletedAt).Should().Be((batchAt, (DateTime?)null));
            var ov = await db.ProductVariants.SingleAsync(x => x.Id == oldVariant);
            (ov.UpdatedAt, ov.DeletedAt).Should().Be((variantAt, (DateTime?)null));
            (await db.ProductSerials.CountAsync(x => x.ProductId == p && x.DeletedAt == null)).Should().Be(3);
            (await db.ProductBatches.CountAsync(x => x.ProductId == p && x.DeletedAt == null)).Should().Be(2);
            (await db.ProductVariants.CountAsync(x => x.ProductId == p && x.DeletedAt == null)).Should().Be(2);
            (await db.StockMovements.Where(m => m.ProductId == p).SumAsync(m => m.QtyMilli)).Should().Be(5000, "3 + 2 new IMEIs");
            (await db.StockMovements.Where(m => m.BatchId == nb).CountAsync()).Should().Be(0, "a new batch starts empty");
        }

        var pages = await PullAllPages(b, cursorB);
        Rows(pages, "products").Single(r => r.GetProperty("id").GetGuid() == p).GetProperty("lowAlertMilli").GetInt64().Should().Be(0);
        Rows(pages, "productSerials").Select(r => r.GetProperty("id").GetGuid()).Should().BeEquivalentTo(new[] { n1, n2 },
            "only the new IMEIs changed, so only they come down");
        Rows(pages, "productBatches").Single(r => r.GetProperty("id").GetGuid() == nb).GetProperty("expiryDate").GetString()
            .Should().StartWith("2028-02-29");
        Rows(pages, "productVariants").Single(r => r.GetProperty("id").GetGuid() == nv).GetProperty("size").GetString().Should().Be("XL");
        Rows(pages, "stockMovements").Sum(m => m.GetProperty("qtyMilli").GetInt64()).Should().Be(2000);
    }

    // TC-SYNC-NEW-5 (risk, record behaviour): phones A and B both receive the SAME IMEI for one product while offline
    // (each makes its own serial row id). README §3.3/§3.4 has no rule for it. Expected at minimum: neither unit is
    // rejected (an outbox must not block). Recorded: how many live rows with that IMEI the server keeps, and whether any
    // SyncIssue is raised.
    [Fact]
    public async Task TC_SYNC_NEW_5_two_phones_receiving_the_same_imei_offline_record_behaviour()
    {
        var a = await NewShop(sql.Api, "phone");
        var b = await Login(sql.Api, a);
        var phone = await AddProduct(a, 0, "QA Dup IMEI");
        var ra = await PushOne(a, Unit("restock", new
        {
            productSerials = new[] { Serial(Guid.CreateVersion7(), phone, "351111111111111") },
            stockMovements = new[] { Restock(phone, 1000) },
        }));
        var rb = await PushOne(b, Unit("restock", new
        {
            productSerials = new[] { Serial(Guid.CreateVersion7(), phone, "351111111111111") },
            stockMovements = new[] { Restock(phone, 1000) },
        }));
        ra.Outcome.Should().Be(UnitOutcome.Applied);
        rb.Outcome.Should().NotBe(UnitOutcome.Rejected, "a rejected unit would block phone B's outbox (TC-SYNC-11)");

        await using var db = sql.CreateContext(a.TenantId);
        var live = await db.ProductSerials.CountAsync(s => s.Serial == "351111111111111" && s.DeletedAt == null);
        var stock = await db.StockMovements.Where(m => m.ProductId == phone).SumAsync(m => m.QtyMilli);
        var issues = await db.SyncIssues.CountAsync();
        Console.WriteLine($"TC-SYNC-NEW-5 recorded: live rows with the IMEI = {live}, stock = {stock}, sync issues = {issues}, " +
                          $"B outcome = {rb.Outcome}, B issues = [{string.Join(",", rb.Issues)}]");
        live.Should().BeGreaterThan(0);
    }
}
