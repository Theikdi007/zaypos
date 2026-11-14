using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Api.Tests;

[Collection(SqlServerCollection.Name)]
public class SyncTests(SqlServerFixture sql)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    // ================================================================ README §7 tests

    [Fact]
    public async Task Pushing_the_same_unit_twice_applies_it_once()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        var checkout = Checkout(shop, "A-0001", (product, 2000, 1500));

        var first = await PushOne(shop, checkout);
        var again = await PushOne(shop, checkout);

        first.Outcome.Should().Be(UnitOutcome.Applied);
        again.Outcome.Should().Be(UnitOutcome.Applied, "a retry answers with the previous outcome");
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.CountAsync()).Should().Be(1);
        (await db.SaleLines.CountAsync()).Should().Be(1);
        (await db.Payments.CountAsync()).Should().Be(1);
        (await db.StockMovements.CountAsync(m => m.Type == StockMovementType.Sale)).Should().Be(1);
        (await Stock(db, product)).Should().Be(8_000);
        (await db.ProcessedUnits.CountAsync(p => p.UnitId == checkout.UnitId)).Should().Be(1);
    }

    [Fact]
    public async Task The_same_unit_pushed_concurrently_is_still_applied_once()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        var checkout = Checkout(shop, "A-0001", (product, 1000, 1500));
        var second = sql.Api.CreateClient();
        second.DefaultRequestHeaders.Authorization = shop.Http.DefaultRequestHeaders.Authorization;

        var results = await Task.WhenAll(
            Push(shop, checkout),
            Push(shop with { Http = second }, checkout));

        results.Should().OnlyContain(r => r[0].Outcome == UnitOutcome.Applied);
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.CountAsync()).Should().Be(1);
        (await Stock(db, product)).Should().Be(9_000);
    }

    [Fact]
    public async Task Checkout_inserts_sale_lines_payment_movements_and_debt_together_with_server_totals()
    {
        var shop = await NewShop();
        var rice = await AddProduct(shop, stock: 50_000);
        var oil = await AddProduct(shop, stock: 10_000);
        var customer = await AddCustomer(shop);

        var cash = Checkout(shop, "A-0001", (rice, 2500, 3000), (oil, 1000, 4500));
        var credit = Checkout(shop, "A-0002", [(rice, 1000, 3000)], method: "debt", customer: customer);
        var results = await Push(shop, cash, credit);

        results.Should().OnlyContain(r => r.Outcome == UnitOutcome.Applied && r.Issues.Count == 0);
        await using var db = sql.CreateContext(shop.TenantId);
        var sales = await db.Sales.OrderBy(s => s.No).ToListAsync();
        sales.Select(s => s.Total).Should().Equal(7500 + 4500, 3000);
        sales[0].ReceivedAt.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromMinutes(1));
        (await db.SaleLines.Where(l => l.SaleId == cash.SaleId).SumAsync(l => l.LineTotal)).Should().Be(12_000);
        (await db.Payments.SingleAsync()).SaleId.Should().Be(cash.SaleId);
        (await Stock(db, rice)).Should().Be(50_000 - 2500 - 1000);
        (await Debt(db, customer)).Should().Be(3000);
    }

    [Fact]
    public async Task A_unit_with_one_bad_row_is_rejected_whole_and_keeps_answering_rejected()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        var unit = Checkout(shop, "A-0001", (product, 1000, 1500));
        unit.Movements.Add(Movement(Guid.CreateVersion7(), 1000, "adjustment")); // unknown product

        var first = await PushOne(shop, unit);
        var retry = await PushOne(shop, unit);

        first.Outcome.Should().Be(UnitOutcome.Rejected);
        first.Reason.Should().Contain("stockMovements.productId");
        retry.Outcome.Should().Be(UnitOutcome.Rejected);
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.AnyAsync()).Should().BeFalse("nothing of a rejected unit is kept");
        (await Stock(db, product)).Should().Be(10_000);
    }

    [Fact]
    public async Task Void_then_void_again_skips_the_second_and_restores_stock_and_debt_once()
    {
        var shop = await NewShop();
        var phoneB = await SecondDevice(shop);
        var product = await AddProduct(shop, stock: 10_000);
        var customer = await AddCustomer(shop);
        var sale = Checkout(shop, "A-0001", [(product, 2000, 1500)], method: "debt", customer: customer);
        await PushOne(shop, sale);

        // Both phones void the same sale offline.
        var voidA = VoidUnit(shop, sale, customer);
        var voidB = VoidUnit(phoneB, sale, customer);
        (await PushOne(shop, voidA)).Outcome.Should().Be(UnitOutcome.Applied);
        (await PushOne(phoneB, voidB)).Outcome.Should().Be(UnitOutcome.Skipped);
        (await PushOne(phoneB, voidB)).Outcome.Should().Be(UnitOutcome.Skipped);

        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.SingleAsync()).VoidedAt.Should().NotBeNull();
        (await Stock(db, product)).Should().Be(10_000);
        (await Debt(db, customer)).Should().Be(0);
        (await db.StockMovements.CountAsync(m => m.Type == StockMovementType.VoidReturn)).Should().Be(1);
    }

    private static TestUnit SerialUnit(Guid product, Guid id, string serial, string status = "inStock") => Unit("restock", new
    {
        productSerials = new[] { new { id, productId = product, serial, status, createdAt = Now(), updatedAt = Now() } },
    });

    [Fact]
    public async Task Two_devices_receiving_the_same_IMEI_keep_both_rows_and_raise_duplicateSerial()
    {
        var shop = await NewShop("phone");
        var phoneB = await SecondDevice(shop);
        var product = await AddProduct(shop, stock: 0);
        var other = await AddProduct(shop, stock: 0);

        (await PushOne(shop, SerialUnit(product, Guid.CreateVersion7(), "351111111111111"))).Issues.Should().BeEmpty();
        var b = await PushOne(phoneB, SerialUnit(product, Guid.CreateVersion7(), "351111111111111"));
        b.Outcome.Should().Be(UnitOutcome.Applied, "never rejected: phone B's outbox must not block");
        b.Issues.Should().Equal(SyncIssueKind.DuplicateSerial);

        // Also across products of the shop.
        var c = await PushOne(shop, SerialUnit(other, Guid.CreateVersion7(), "351111111111111"));
        c.Issues.Should().Equal(SyncIssueKind.DuplicateSerial);

        await using var db = sql.CreateContext(shop.TenantId);
        (await db.ProductSerials.CountAsync(s => s.Serial == "351111111111111")).Should().Be(3, "all rows are kept");
        var issue = await db.SyncIssues.FirstAsync(i => i.Kind == SyncIssueKind.DuplicateSerial);
        issue.EntityTable.Should().Be("ProductSerials");
        issue.Detail.Should().Contain("351111111111111");
    }

    [Fact]
    public async Task A_new_IMEI_matching_only_a_sold_one_or_a_resent_row_raises_no_duplicateSerial()
    {
        var shop = await NewShop("phone");
        var product = await AddProduct(shop, stock: 0);
        await PushOne(shop, SerialUnit(product, Guid.CreateVersion7(), "352222222222222", status: "sold"));
        (await PushOne(shop, SerialUnit(product, Guid.CreateVersion7(), "352222222222222"))).Issues.Should().BeEmpty(
            "the sold phone came back / was traded in: only in-stock duplicates matter");

        var id = Guid.CreateVersion7();
        await PushOne(shop, SerialUnit(product, id, "353333333333333"));
        (await PushOne(shop, SerialUnit(product, id, "353333333333333"))).Issues.Should().BeEmpty("same row again is not a duplicate");
    }

    [Fact]
    public async Task Two_devices_selling_the_same_IMEI_keep_both_sales_and_raise_serialDoubleSold()
    {
        var shop = await NewShop("phone");
        var phoneB = await SecondDevice(shop);
        var product = await AddProduct(shop, stock: 2000); // stock itself never goes negative here
        var serialId = Guid.CreateVersion7();
        await PushOne(shop, Unit("upsertProduct", new
        {
            productSerials = new[] { new { id = serialId, productId = product, serial = "356938035643809", status = "inStock", createdAt = Now(), updatedAt = Now() } },
        }));

        var saleA = Checkout(shop, "A-0001", [(product, 1000, 900_000)], serialId: serialId);
        var saleB = Checkout(phoneB, "B-0001", [(product, 1000, 900_000)], serialId: serialId);
        (await PushOne(shop, saleA)).Issues.Should().BeEmpty();
        var b = await PushOne(phoneB, saleB);

        b.Outcome.Should().Be(UnitOutcome.Applied);
        b.Issues.Should().Equal(SyncIssueKind.SerialDoubleSold);
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.CountAsync()).Should().Be(2);
        var serial = await db.ProductSerials.SingleAsync();
        serial.Status.Should().Be(SerialStatus.Sold);
        serial.SaleLineId.Should().Be(saleA.LineIds[0], "the first sale keeps the serial");
        (await db.SyncIssues.SingleAsync()).EntityId.Should().Be(serialId);
    }

    [Fact]
    public async Task Selling_below_zero_keeps_the_sale_and_raises_negativeStock_once()
    {
        var shop = await NewShop(); // grocery: stock feature on
        var product = await AddProduct(shop, stock: 1000);

        var r1 = await PushOne(shop, Checkout(shop, "A-0001", (product, 3000, 500)));
        var r2 = await PushOne(shop, Checkout(shop, "A-0002", (product, 1000, 500)));

        r1.Outcome.Should().Be(UnitOutcome.Applied);
        r1.Issues.Should().Equal(SyncIssueKind.NegativeStock);
        r2.Issues.Should().BeEmpty("already negative: the owner was told once");
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.CountAsync()).Should().Be(2);
        (await Stock(db, product)).Should().Be(-3000);
        (await db.SyncIssues.SingleAsync()).Detail.Should().Contain("-2");
    }

    [Fact]
    public async Task Untracked_products_never_raise_negativeStock_until_counted_in()
    {
        var shop = await NewShop(); // grocery: stock feature on
        var preset = await AddProduct(shop, stock: 0); // imported preset: no movements
        var counted = await AddProduct(shop, stock: 0);

        // Sales, a void return and a negative adjustment do not start tracking.
        var sale = Checkout(shop, "A-0001", (preset, 2000, 500));
        (await PushOne(shop, sale)).Issues.Should().BeEmpty("never counted in: the ledger means nothing yet");
        (await PushOne(shop, VoidUnit(shop, sale, null))).Issues.Should().BeEmpty();
        (await PushOne(shop, Unit("stockAdjust", new { stockMovements = new[] { Movement(preset, -1000, "adjustment") } })))
            .Issues.Should().BeEmpty();
        (await PushOne(shop, Checkout(shop, "A-0002", (preset, 1000, 500)))).Issues.Should().BeEmpty();

        // A deleted restock does not count either.
        var t = Now();
        (await PushOne(shop, Unit("restock", new
        {
            stockMovements = new[] { new { id = Guid.CreateVersion7(), productId = counted, type = "restock", qtyMilli = 5000L, createdAt = t, updatedAt = t, deletedAt = (DateTime?)t } },
        }))).Outcome.Should().Be(UnitOutcome.Applied);
        (await PushOne(shop, Checkout(shop, "A-0003", (counted, 1000, 500)))).Issues.Should().BeEmpty();

        // Counted in (adjustment > 0, the mobile opening count): tracked from now on.
        (await PushOne(shop, Unit("stockAdjust", new { stockMovements = new[] { Movement(counted, 3000, "adjustment") } })))
            .Issues.Should().BeEmpty();
        var r = await PushOne(shop, Checkout(shop, "A-0004", (counted, 4000, 500)));
        r.Issues.Should().Equal(SyncIssueKind.NegativeStock);

        await using var db = sql.CreateContext(shop.TenantId);
        (await Stock(db, preset)).Should().Be(-2000);
        (await db.SyncIssues.SingleAsync()).EntityId.Should().Be(counted);
    }

    [Fact]
    public async Task Pull_returns_rows_after_the_cursor_in_pages_and_never_another_tenants_rows()
    {
        var shop = await NewShop();
        var other = await NewShop();
        for (var i = 0; i < 5; i++) await AddProduct(shop, stock: 0);
        var foreign = await AddProduct(other, stock: 1000);

        var seen = new List<Guid>();
        string cursor = "0";
        var pages = 0;
        PullResponse page;
        do
        {
            page = await Pull(shop, cursor, limit: 3);
            seen.AddRange(page.Changes.Products.Select(p => p.Id));
            seen.AddRange(page.Changes.StockMovements.Select(m => m.Id));
            AllRows(page).Should().OnlyContain(r => r.TenantId == shop.TenantId);
            AllRows(page).Count().Should().BeLessThanOrEqualTo(3);
            if (page.HasMore) string.CompareOrdinal(page.Cursor, cursor).Should().BePositive();
            cursor = page.Cursor;
            pages++;
        } while (page.HasMore);

        pages.Should().BeGreaterThan(1);
        seen.Should().OnlyHaveUniqueItems();
        seen.Should().NotContain(foreign);
        await using (var db = sql.CreateContext(shop.TenantId))
            seen.Where(id => db.Products.Any(p => p.Id == id)).Should().HaveCount(5);

        // Nothing new → empty page, same cursor. A new row → only that row.
        var empty = await Pull(shop, cursor);
        AllRows(empty).Should().BeEmpty();
        empty.Cursor.Should().Be(cursor);
        var added = await AddProduct(shop, stock: 0);
        (await Pull(shop, cursor)).Changes.Products.Select(p => p.Id).Should().Equal(added);
    }

    [Fact]
    public async Task Products_are_last_writer_wins_and_future_edits_are_clamped_with_clockSkew()
    {
        var shop = await NewShop();
        var id = Guid.CreateVersion7();
        var t0 = Now().AddMinutes(-10);
        await PushOne(shop, ProductUnit(id, "v1", t0));

        await PushOne(shop, ProductUnit(id, "older", t0.AddMinutes(-1)));
        (await ProductName(shop, id)).Should().Be("v1");

        await PushOne(shop, ProductUnit(id, "newer", t0.AddMinutes(1)));
        (await ProductName(shop, id)).Should().Be("newer");

        var future = await PushOne(shop, ProductUnit(id, "from the future", Now().AddHours(3)));
        future.Issues.Should().Equal(SyncIssueKind.ClockSkew);
        await using var db = sql.CreateContext(shop.TenantId);
        var p = await db.Products.SingleAsync(x => x.Id == id);
        p.Name.Should().Be("from the future");
        p.UpdatedAt.Should().BeOnOrBefore(DateTime.UtcNow.AddMinutes(5).AddSeconds(5)).And.BeAfter(DateTime.UtcNow.AddMinutes(4));
    }

    // ================================================================ more table rules

    [Fact]
    public async Task Delete_wins_over_later_edits_until_explicitly_restored()
    {
        var shop = await NewShop();
        var id = Guid.CreateVersion7();
        var t = Now().AddMinutes(-30);
        await PushOne(shop, ProductUnit(id, "v1", t));
        await PushOne(shop, ProductUnit(id, "edited later", t.AddMinutes(10)));

        await PushOne(shop, ProductUnit(id, "v1", t.AddMinutes(5), deletedAt: t.AddMinutes(5))); // older, but deletes
        (await LoadProduct(shop, id)).Should().Match<Product>(p => p.DeletedAt != null && p.Name == "edited later");

        await PushOne(shop, ProductUnit(id, "edit after delete", t.AddMinutes(20)));
        (await LoadProduct(shop, id)).DeletedAt.Should().NotBeNull("a deleted item stays deleted");

        await PushOne(shop, ProductUnit(id, "restored", t.AddMinutes(21), restore: true));
        (await LoadProduct(shop, id)).Should().Match<Product>(p => p.DeletedAt == null && p.Name == "restored");
    }

    [Fact]
    public async Task Client_totals_are_recomputed_and_mismatch_is_reported()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        var unit = Checkout(shop, "A-0001", [(product, 2500, 333)], clientTotal: 800);

        var r = await PushOne(shop, unit);

        r.Issues.Should().Equal(SyncIssueKind.TotalMismatch);
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.SingleAsync()).Total.Should().Be(833, "333 × 2.5 = 832.5 → 833");
    }

    [Fact]
    public async Task Credit_sale_over_the_limit_is_kept_with_creditLimitExceeded()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        var customer = await AddCustomer(shop, creditLimit: 5000);

        var r = await PushOne(shop, Checkout(shop, "A-0001", [(product, 2000, 3000)], method: "debt", customer: customer));

        r.Issues.Should().Equal(SyncIssueKind.CreditLimitExceeded);
        await using var db = sql.CreateContext(shop.TenantId);
        (await Debt(db, customer)).Should().Be(6000);
    }

    [Fact]
    public async Task Two_live_products_with_one_barcode_raise_duplicateBarcode()
    {
        var shop = await NewShop();
        await PushOne(shop, ProductUnit(Guid.CreateVersion7(), "Coke A", Now(), barcode: "8850999320014"));
        var second = await PushOne(shop, ProductUnit(Guid.CreateVersion7(), "Coke B", Now(), barcode: "8850999320014"));
        second.Issues.Should().Equal(SyncIssueKind.DuplicateBarcode);
    }

    [Fact]
    public async Task Device_lastSeq_only_moves_forward()
    {
        var shop = await NewShop();
        await PushOne(shop, Unit("checkout", new { devices = new[] { new { id = shop.DeviceId, lastSeq = 12 } } }));
        await PushOne(shop, Unit("checkout", new { devices = new[] { new { id = shop.DeviceId, lastSeq = 7 } } }));

        await using var db = sql.CreateContext(shop.TenantId);
        var device = await db.Devices.SingleAsync(d => d.Id == shop.DeviceId);
        device.LastSeq.Should().Be(12);
        device.LastSyncAt.Should().NotBeNull();
    }

    [Fact]
    public async Task A_reused_receipt_number_is_kept_under_a_suffix_with_an_issue()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 10_000);
        await PushOne(shop, Checkout(shop, "A-0001", (product, 1000, 100)));
        var dup = await PushOne(shop, Checkout(shop, "A-0001", (product, 1000, 100)));

        dup.Outcome.Should().Be(UnitOutcome.Applied);
        dup.Issues.Should().Equal(SyncIssueKind.DuplicateReceiptNo);
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.Select(s => s.No).OrderBy(n => n).ToListAsync()).Should().Equal("A-0001", "A-0001*2");
    }

    // ================================================================ shape, security

    [Fact]
    public async Task Rows_of_another_tenant_and_malformed_numbers_are_rejected()
    {
        var shop = await NewShop();
        var other = await NewShop();
        var foreignRow = Unit("upsertProduct", new { products = new[] { ProductRowFor(Guid.CreateVersion7(), "x", Now(), tenantId: other.TenantId) } });
        var stringQty = Unit("restock", JsonDocument.Parse("""{"stockMovements":[{"id":"0193a0c0-0000-7000-8000-000000000001","productId":"0193a0c0-0000-7000-8000-000000000002","type":"restock","qtyMilli":"1000","createdAt":"2026-11-11T09:00:00Z","updatedAt":"2026-11-11T09:00:00Z"}]}""").RootElement);
        var fraction = Unit("restock", JsonDocument.Parse("""{"stockMovements":[{"id":"0193a0c0-0000-7000-8000-000000000003","productId":"0193a0c0-0000-7000-8000-000000000002","type":"restock","qtyMilli":1.5,"createdAt":"2026-11-11T09:00:00Z","updatedAt":"2026-11-11T09:00:00Z"}]}""").RootElement);
        var unknownKind = Unit("teleport", new { });

        var results = await Push(shop, foreignRow, stringQty, fraction, unknownKind);

        results.Should().OnlyContain(r => r.Outcome == UnitOutcome.Rejected && r.Reason != null);
        results[0].Reason.Should().Contain("another tenant");
        await using var db = sql.CreateContext(other.TenantId);
        (await db.Products.AnyAsync()).Should().BeFalse();
    }

    [Fact]
    public async Task Ids_of_another_tenants_rows_cannot_be_overwritten()
    {
        var victim = await NewShop();
        var attacker = await NewShop();
        var victimProduct = await AddProduct(victim, stock: 0);

        var r = await PushOne(attacker, ProductUnit(victimProduct, "hijacked", Now().AddMinutes(1)));

        r.Outcome.Should().Be(UnitOutcome.Rejected);
        (await ProductName(victim, victimProduct)).Should().NotBe("hijacked");
    }

    [Fact]
    public async Task Sync_needs_a_token_for_this_device_and_an_active_device()
    {
        var shop = await NewShop();
        var anonymous = sql.Api.CreateClient();
        (await anonymous.GetAsync("/api/v1/sync/pull?cursor=0")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var wrongDevice = await shop.Http.PostAsJsonAsync("/api/v1/sync/push",
            new { deviceId = Guid.CreateVersion7(), units = new[] { Unit("checkout", new { }) } }, Json);
        wrongDevice.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        await using (var db = sql.CreateContext(shop.TenantId))
        {
            (await db.Devices.SingleAsync()).DeletedAt = DateTime.UtcNow; // owner revoked the phone
            await db.SaveChangesAsync();
        }
        (await shop.Http.GetAsync("/api/v1/sync/pull?cursor=0")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Pull_never_moves_past_a_row_still_being_written()
    {
        var shop = await NewShop();
        await AddProduct(shop, stock: 0);
        var cursor = (await PullAll(shop)).Cursor;

        await using var slow = sql.CreateContext(shop.TenantId);
        await using var tx = await slow.Database.BeginTransactionAsync();
        var slowId = Guid.CreateVersion7();
        slow.Products.Add(NewProductEntity(shop, slowId, "slow writer"));
        await slow.SaveChangesAsync(); // holds a LOWER rowversion, not committed yet

        var fast = await AddProduct(shop, stock: 0); // committed, HIGHER rowversion

        var during = await Pull(shop, cursor);
        during.Changes.Products.Should().BeEmpty("rows at or after MIN_ACTIVE_ROWVERSION() wait for the open transaction");
        during.Cursor.Should().Be(cursor);

        await tx.CommitAsync();
        var after = await Pull(shop, cursor);
        after.Changes.Products.Select(p => p.Id).Should().BeEquivalentTo([slowId, fast]);
    }

    [Fact]
    public async Task Pull_includes_soft_deleted_rows_and_sync_issues()
    {
        var shop = await NewShop();
        var id = Guid.CreateVersion7();
        await PushOne(shop, ProductUnit(id, "gone", Now(), deletedAt: Now()));
        var product = await AddProduct(shop, stock: 500); // tracked: selling 1000 goes negative
        await PushOne(shop, Checkout(shop, "A-0001", (product, 1000, 100))); // negative stock issue

        var page = await PullAll(shop);

        page.Changes.Products.Single(p => p.Id == id).DeletedAt.Should().NotBeNull();
        page.Changes.SyncIssues.Should().ContainSingle(i => i.Kind == SyncIssueKind.NegativeStock);
        page.Changes.Sales.Single().SyncedAt.Should().NotBeNull();
        page.Changes.TenantFeatures.Should().HaveCount(FeatureKeys.All.Count);
    }

    [Fact]
    public async Task Owner_resolves_a_sync_issue_once_and_every_phone_pulls_it()
    {
        var shop = await NewShop();
        var product = await AddProduct(shop, stock: 500); // tracked: selling 1000 goes negative
        await PushOne(shop, Checkout(shop, "A-0001", (product, 1000, 100))); // negative stock issue
        var cursor = (await PullAll(shop)).Cursor;
        Guid issueId;
        await using (var db = sql.CreateContext(shop.TenantId))
            issueId = (await db.SyncIssues.SingleAsync()).Id;

        var first = await Resolve(shop, issueId);
        first.StatusCode.Should().Be(HttpStatusCode.OK, await first.Content.ReadAsStringAsync());
        var resolved = (await first.Content.ReadFromJsonAsync<SyncIssueRow>(Json))!;
        resolved.ResolvedAt.Should().NotBeNull();
        resolved.UpdatedAt.Should().Be(resolved.ResolvedAt!.Value);

        var again = await Resolve(shop, issueId);
        again.StatusCode.Should().Be(HttpStatusCode.OK);
        (await again.Content.ReadFromJsonAsync<SyncIssueRow>(Json))!.ResolvedAt.Should().Be(resolved.ResolvedAt, "idempotent");

        var page = await Pull(shop, cursor);
        page.Changes.SyncIssues.Should().ContainSingle(i => i.Id == issueId && i.ResolvedAt == resolved.ResolvedAt);
        (await Pull(shop, page.Cursor)).Changes.SyncIssues.Should().BeEmpty("the second resolve changed nothing");
    }

    [Fact]
    public async Task Resolving_needs_the_owner_and_an_issue_of_this_shop()
    {
        var shop = await NewShop();
        var other = await NewShop();
        var product = await AddProduct(shop, stock: 500); // tracked: selling 1000 goes negative
        await PushOne(shop, Checkout(shop, "A-0001", (product, 1000, 100)));
        Guid issueId;
        await using (var db = sql.CreateContext(shop.TenantId))
        {
            issueId = (await db.SyncIssues.SingleAsync()).Id;
            (await db.Users.SingleAsync()).Role = UserRole.Staff;
            await db.SaveChangesAsync();
        }
        var staff = await SecondDevice(shop); // signs in after the role change → staff token

        (await Resolve(staff, issueId)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await Resolve(other, issueId)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await Resolve(shop, Guid.CreateVersion7())).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await sql.Api.CreateClient().PostAsync($"/api/v1/sync/issues/{issueId}/resolve", null))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        await using (var db = sql.CreateContext(shop.TenantId))
            (await db.SyncIssues.SingleAsync()).ResolvedAt.Should().BeNull();
    }

    private static Task<HttpResponseMessage> Resolve(Shop shop, Guid issueId) =>
        shop.Http.PostAsync($"/api/v1/sync/issues/{issueId}/resolve", null);

    // ================================================================ helpers: shops

    private sealed record Shop(HttpClient Http, AuthResponse Auth, string Phone)
    {
        public Guid TenantId => Auth.Tenant.Id;
        public Guid DeviceId => Auth.Device.Id;
    }

    private async Task<Shop> NewShop(string template = "grocery")
    {
        var http = sql.Api.CreateClient();
        var phone = "+9596" + Interlocked.Increment(ref _seq).ToString("D8");
        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var res = await http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(phone, sql.Api.Sms.LastCode(phone), "Sync shop", template, null, "123456",
                new DeviceInfo(Guid.CreateVersion7(), "A15")), Json);
        res.EnsureSuccessStatusCode();
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new Shop(http, auth, phone);
    }

    private async Task<Shop> SecondDevice(Shop shop)
    {
        var http = sql.Api.CreateClient();
        var res = await http.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(shop.Phone, "123456", new DeviceInfo(Guid.CreateVersion7(), "Redmi")), Json);
        res.EnsureSuccessStatusCode();
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new Shop(http, auth, shop.Phone);
    }

    // ================================================================ helpers: units

    private sealed class TestUnit
    {
        public Guid UnitId { get; } = Guid.CreateVersion7();
        public required string Kind { get; init; }
        public DateTime ClientTime { get; init; } = Now();
        public object Rows { get; set; } = new { };
        // checkout bookkeeping
        public Guid SaleId { get; init; }
        public long Total { get; init; }
        public List<Guid> LineIds { get; } = [];
        public List<(Guid Product, long Qty)> Sold { get; } = [];
        public List<object> Movements { get; } = [];
        public object Wire() => new { unitId = UnitId, kind = Kind, clientTime = ClientTime, rows = Rows };
    }

    private static TestUnit Unit(string kind, object rows) => new() { Kind = kind, Rows = rows };

    private static TestUnit Checkout(Shop shop, string no, params (Guid Product, long Qty, long Price)[] lines) =>
        Checkout(shop, no, lines, method: "cash");

    private static TestUnit Checkout(Shop shop, string no, (Guid Product, long Qty, long Price)[] lines,
        string method = "cash", Guid? customer = null, Guid? serialId = null, long? clientTotal = null)
    {
        var t = Now();
        var saleId = Guid.CreateVersion7();
        var lineRows = new List<object>();
        var total = lines.Sum(l => Ledger.LineTotal(l.Price, l.Qty));
        var unit = new TestUnit { Kind = "checkout", SaleId = saleId, Total = total };
        foreach (var (product, qty, price) in lines)
        {
            var lineId = Guid.CreateVersion7();
            unit.LineIds.Add(lineId);
            unit.Sold.Add((product, qty));
            lineRows.Add(new
            {
                id = lineId, tenantId = shop.TenantId, saleId, productId = product, serialId, name = "item",
                qtyMilli = qty, price, costSnapshot = price / 2, lineTotal = Ledger.LineTotal(price, qty),
                createdAt = t, updatedAt = t,
            });
            unit.Movements.Add(Movement(product, -qty, "sale", saleId));
        }
        var payments = method == "debt"
            ? Array.Empty<object>()
            : [new { id = Guid.CreateVersion7(), saleId, method, amount = total, received = total, createdAt = t, updatedAt = t }];
        var debt = method == "debt"
            ? new object[] { new { id = Guid.CreateVersion7(), customerId = customer, type = "creditSale", amount = total, saleId, saleNo = no, createdAt = t, updatedAt = t } }
            : [];
        var serials = serialId is { } s
            ? new object[] { new { id = s, status = "sold", saleLineId = unit.LineIds[0], updatedAt = t } }
            : [];
        unit.Rows = new
        {
            sales = new[] { new { id = saleId, tenantId = shop.TenantId, no, method, customerId = customer, total = clientTotal ?? total, createdAt = t, updatedAt = t } },
            saleLines = lineRows,
            payments,
            stockMovements = unit.Movements,
            debtEntries = debt,
            productSerials = serials,
        };
        return unit;
    }

    private static TestUnit VoidUnit(Shop by, TestUnit sale, Guid? customer)
    {
        var t = Now();
        var movements = sale.Sold.Select(s => Movement(s.Product, s.Qty, "voidReturn", sale.SaleId)).ToArray();
        var debt = customer is null
            ? Array.Empty<object>()
            : [new { id = Guid.CreateVersion7(), customerId = customer, type = "adjustment", amount = -sale.Total, saleId = sale.SaleId, note = "void", createdAt = t, updatedAt = t }];
        return Unit("voidSale", new
        {
            sales = new[] { new { id = sale.SaleId, voidedAt = t, updatedAt = t } },
            stockMovements = movements,
            debtEntries = debt,
        });
    }

    private static object Movement(Guid product, long qty, string type, Guid? saleId = null)
    {
        var t = Now();
        return new { id = Guid.CreateVersion7(), productId = product, type, qtyMilli = qty, saleId, createdAt = t, updatedAt = t };
    }

    private static object ProductRowFor(Guid id, string name, DateTime updatedAt, DateTime? deletedAt = null,
        bool? restore = null, string? barcode = null, Guid? tenantId = null) => new
    {
        id, tenantId, name, category = "General", unit = "ခု", barcode, cost = 1000, price = 1500, lowAlertMilli = 5000,
        tint = unchecked((int)0xFFE0F2F1), initial = "က", createdAt = updatedAt.AddMinutes(-1), updatedAt, deletedAt, restore,
    };

    private static TestUnit ProductUnit(Guid id, string name, DateTime updatedAt, DateTime? deletedAt = null,
        bool? restore = null, string? barcode = null) =>
        Unit("upsertProduct", new { products = new[] { ProductRowFor(id, name, updatedAt, deletedAt, restore, barcode) } });

    private async Task<Guid> AddProduct(Shop shop, long stock)
    {
        var id = Guid.CreateVersion7();
        var unit = ProductUnit(id, "product " + id.ToString()[..8], Now());
        if (stock != 0)
            unit.Rows = new
            {
                products = new[] { ProductRowFor(id, "product", Now()) },
                stockMovements = new[] { Movement(id, stock, "restock") },
            };
        (await PushOne(shop, unit)).Outcome.Should().Be(UnitOutcome.Applied);
        return id;
    }

    private async Task<Guid> AddCustomer(Shop shop, long? creditLimit = null)
    {
        var id = Guid.CreateVersion7();
        var r = await PushOne(shop, Unit("upsertCustomer", new
        {
            customers = new[] { new { id, name = "ဒေါ်ခင်မာ", phone = "09 ၇၇၇ ၁၂၃ ၄၅၆", creditLimit, createdAt = Now(), updatedAt = Now() } },
        }));
        r.Outcome.Should().Be(UnitOutcome.Applied, r.Reason);
        return id;
    }

    private static ZayPOS.Domain.Catalog.Product NewProductEntity(Shop shop, Guid id, string name) => new()
    {
        Id = id, TenantId = shop.TenantId, Name = name, Category = "General", Unit = "ခု", Cost = 1, Price = 2,
        LowAlertMilli = 0, Tint = 0, Initial = "s", CreatedAt = Now(), UpdatedAt = Now(),
    };

    // ================================================================ helpers: HTTP + DB

    private static async Task<List<UnitResult>> Push(Shop shop, params TestUnit[] units)
    {
        var res = await shop.Http.PostAsJsonAsync("/api/v1/sync/push",
            new { deviceId = shop.DeviceId, units = units.Select(u => u.Wire()) }, Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var body = (await res.Content.ReadFromJsonAsync<PushResponse>(Json))!;
        body.Results.Select(r => r.UnitId).Should().Equal(units.Select(u => u.UnitId));
        return [.. body.Results];
    }

    private static async Task<UnitResult> PushOne(Shop shop, TestUnit unit) => (await Push(shop, unit))[0];

    private static async Task<PullResponse> Pull(Shop shop, string cursor, int limit = 500)
    {
        var res = await shop.Http.GetAsync($"/api/v1/sync/pull?cursor={cursor}&limit={limit}");
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<PullResponse>(Json))!;
    }

    private static async Task<PullResponse> PullAll(Shop shop)
    {
        var page = await Pull(shop, "0", 1000);
        page.HasMore.Should().BeFalse();
        return page;
    }

    private static IEnumerable<(Guid? TenantId, Guid Id)> AllRows(PullResponse p)
    {
        var c = p.Changes;
        IEnumerable<SyncRow> rows = [.. c.Tenants, .. c.Devices, .. c.Products, .. c.ProductVariants, .. c.ProductBatches,
            .. c.ProductSerials, .. c.Customers, .. c.Sales, .. c.SaleLines, .. c.Payments, .. c.StockMovements,
            .. c.DebtEntries, .. c.SyncIssues];
        return rows.Select(r => (r.TenantId, r.Id)).Concat(c.TenantFeatures.Select(f => (f.TenantId, Guid.Empty)));
    }

    private static Task<long> Stock(ZayPOS.Infrastructure.Persistence.ZayPosDbContext db, Guid product) =>
        db.StockMovements.Where(m => m.ProductId == product && m.DeletedAt == null).SumAsync(m => m.QtyMilli);

    private static async Task<long> Debt(ZayPOS.Infrastructure.Persistence.ZayPosDbContext db, Guid customer) =>
        (await db.DebtEntries.Where(e => e.CustomerId == customer && e.DeletedAt == null).ToListAsync()).Sum(e => e.Effect);

    private async Task<Product> LoadProduct(Shop shop, Guid id)
    {
        await using var db = sql.CreateContext(shop.TenantId);
        return await db.Products.AsNoTracking().SingleAsync(p => p.Id == id);
    }

    private async Task<string?> ProductName(Shop shop, Guid id)
    {
        await using var db = sql.CreateContext(shop.TenantId);
        return await db.Products.Where(p => p.Id == id).Select(p => p.Name).SingleOrDefaultAsync();
    }

    private static DateTime Now() => SyncJson.ToUtcMs(DateTime.UtcNow);
}
