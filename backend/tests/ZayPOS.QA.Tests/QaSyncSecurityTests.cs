using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>QA round 1 — POS/SYNC/SEC cases proven against the real API + SQL Server.</summary>
[Collection(QaSqlCollection.Name)]
public class QaSyncSecurityTests(SqlServerFixture sql)
{
    // TC-POS-10 (server half): 600 Ks × 2.5 = 1,500 Ks, line and sale total, no totalMismatch.
    [Fact]
    public async Task TC_POS_10_server_total_for_600_times_2_5_is_1500()
    {
        var shop = await NewShop(sql.Api, "hardware");
        var product = await AddProduct(shop, 10_000);
        var (unit, saleId) = Checkout(shop, "A-0001", product, 2500, 600, clientTotal: 1500, clientLineTotal: 1500);

        var r = await PushOne(shop, unit);

        r.Outcome.Should().Be(UnitOutcome.Applied);
        r.Issues.Should().BeEmpty("the app's Qty.lineTotal and the server agree");
        await using var db = sql.CreateContext(shop.TenantId);
        (await db.Sales.SingleAsync(s => s.Id == saleId)).Total.Should().Be(1500);
        (await db.SaleLines.SingleAsync(l => l.SaleId == saleId)).LineTotal.Should().Be(1500);
    }

    // TC-SEC-01: shop X pulls everything from cursor 0 — no row of shop Y in ANY table.
    [Fact]
    public async Task TC_SEC_01_pull_never_returns_any_row_of_another_shop()
    {
        var y = await NewShop(sql.Api, "phone");
        var yB = await Login(sql.Api, y);
        var yProduct = await AddProduct(y, 5000, "Y secret product");
        var yCustomer = await AddCustomer(y, creditLimit: 1);
        var (credit, _) = Checkout(y, "A-0001", yProduct, 7000, 1000, method: "debt", customer: yCustomer); // negativeStock + creditLimit issues
        await PushOne(y, credit);
        var (cash, _) = Checkout(yB, "B-0001", yProduct, 1000, 1000);
        await PushOne(yB, cash);

        var x = await NewShop(sql.Api);
        await AddProduct(x, 1000);

        Guid[] yIds;
        await using (var db = sql.CreateContext(y.TenantId))
        {
            yIds = [y.TenantId, y.DeviceId, yB.DeviceId, y.Auth.User.Id,
                .. await db.Products.Select(p => p.Id).ToListAsync(),
                .. await db.Customers.Select(p => p.Id).ToListAsync(),
                .. await db.Sales.Select(p => p.Id).ToListAsync(),
                .. await db.SaleLines.Select(p => p.Id).ToListAsync(),
                .. await db.Payments.Select(p => p.Id).ToListAsync(),
                .. await db.StockMovements.Select(p => p.Id).ToListAsync(),
                .. await db.DebtEntries.Select(p => p.Id).ToListAsync(),
                .. await db.SyncIssues.Select(p => p.Id).ToListAsync()];
            (await db.SyncIssues.CountAsync()).Should().BeGreaterThan(0);
        }

        var pages = await PullAllPages(x);
        var text = string.Join("\n", pages.Select(p => p.GetRawText()));
        foreach (var id in yIds)
            text.Should().NotContain(id.ToString(), "shop X must never see a row of shop Y");
        text.Should().NotContain("Y secret product");

        // Every returned row carries X's tenant (where the row has a tenantId).
        foreach (var page in pages)
            foreach (var table in page.GetProperty("changes").EnumerateObject())
                foreach (var row in table.Value.EnumerateArray())
                    if (row.TryGetProperty("tenantId", out var tid) && tid.ValueKind == JsonValueKind.String)
                        tid.GetGuid().Should().Be(x.TenantId, table.Name);
    }

    // TC-SEC-02: X pushes rows that reuse ids of Y's sale / customer / stock movement → rejected, Y unchanged.
    [Fact]
    public async Task TC_SEC_02_existing_ids_of_another_shop_are_rejected_and_left_untouched()
    {
        var y = await NewShop(sql.Api);
        var yProduct = await AddProduct(y, 5000);
        var yCustomer = await AddCustomer(y);
        var (sale, ySaleId) = Checkout(y, "A-0001", yProduct, 1000, 1000, method: "debt", customer: yCustomer);
        await PushOne(y, sale);
        Guid yMovementId;
        await using (var db = sql.CreateContext(y.TenantId))
            yMovementId = await db.StockMovements.Where(m => m.Type == StockMovementType.Sale).Select(m => m.Id).SingleAsync();

        var x = await NewShop(sql.Api);
        var xProduct = await AddProduct(x, 5000);
        var t = Now();

        var results = await Push(x,
            // void Y's sale from shop X
            Unit("voidSale", new { sales = new[] { new { id = ySaleId, voidedAt = t, updatedAt = t } } }),
            // overwrite Y's customer
            Unit("upsertCustomer", new { customers = new[] { new { id = yCustomer, name = "hijacked", phone = "", createdAt = t, updatedAt = t.AddMinutes(1) } } }),
            // insert a movement with Y's movement id
            Unit("restock", new { stockMovements = new[] { new { id = yMovementId, productId = xProduct, type = "restock", qtyMilli = 1000L, createdAt = t, updatedAt = t } } }),
            // a sale with Y's sale id
            Checkout(x, "A-0001", xProduct, 1000, 1000).Unit);

        // The checkout above uses a fresh sale id; re-push one that reuses Y's sale id.
        var reuse = Unit("checkout", new
        {
            sales = new[] { new { id = ySaleId, no = "A-0002", method = "cash", total = 1000L, createdAt = t, updatedAt = t } },
            saleLines = new[] { new { id = Guid.CreateVersion7(), saleId = ySaleId, productId = xProduct, name = "x", qtyMilli = 1000L, price = 1000L, costSnapshot = 0L, lineTotal = 1000L, createdAt = t, updatedAt = t } },
        });
        var reuseResult = await PushOne(x, reuse);

        results[0].Outcome.Should().Be(UnitOutcome.Rejected, "voidSale of another shop's sale");
        results[1].Outcome.Should().Be(UnitOutcome.Rejected, "customer id of another shop");
        results[2].Outcome.Should().Be(UnitOutcome.Rejected, "movement id of another shop");
        results[3].Outcome.Should().Be(UnitOutcome.Applied, "control: a normal sale of X");
        reuseResult.Outcome.Should().Be(UnitOutcome.Rejected, "sale id of another shop");

        await using var ydb = sql.CreateContext(y.TenantId);
        (await ydb.Sales.SingleAsync()).VoidedAt.Should().BeNull();
        (await ydb.Customers.SingleAsync()).Name.Should().Be("QA customer");
        (await ydb.StockMovements.SingleAsync(m => m.Id == yMovementId)).ProductId.Should().Be(yProduct);
        (await ydb.Sales.CountAsync()).Should().Be(1);
    }

    // TC-SEC-03: no token → 401 on /sync, /me, /devices; revoked device → 403 with code device_revoked on each.
    [Fact]
    public async Task TC_SEC_03_no_token_is_401_and_a_revoked_device_is_403_device_revoked_everywhere()
    {
        var anon = sql.Api.CreateClient();
        (await anon.GetAsync("/api/v1/sync/pull?cursor=0")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.PostAsJsonAsync("/api/v1/sync/push", new { deviceId = Guid.NewGuid(), units = Array.Empty<object>() }))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.GetAsync("/api/v1/me")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.GetAsync("/api/v1/devices")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var shop = await NewShop(sql.Api);
        var lost = await Login(sql.Api, shop);
        (await shop.Http.DeleteAsync($"/api/v1/devices/{lost.DeviceId}")).StatusCode.Should().Be(HttpStatusCode.NoContent);

        var calls = new (string Name, Func<Task<HttpResponseMessage>> Call)[]
        {
            ("pull", () => lost.Http.GetAsync("/api/v1/sync/pull?cursor=0")),
            ("push", () => lost.Http.PostAsJsonAsync("/api/v1/sync/push",
                new { deviceId = lost.DeviceId, units = new[] { Unit("upsertProduct", new { products = new[] { Product(Guid.CreateVersion7()) } }) } }, Json)),
            ("me", () => lost.Http.GetAsync("/api/v1/me")),
            ("devices", () => lost.Http.GetAsync("/api/v1/devices")),
            ("refresh", () => sql.Api.CreateClient().PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = lost.Auth.RefreshToken }, Json)),
        };
        foreach (var (name, call) in calls)
        {
            var res = await call();
            var body = await res.Content.ReadAsStringAsync();
            if (name == "refresh")
            {
                ((int)res.StatusCode).Should().BeOneOf([401, 403], name);
                continue;
            }
            res.StatusCode.Should().Be(HttpStatusCode.Forbidden, $"{name}: {body}");
            JsonDocument.Parse(body).RootElement.GetProperty("code").GetString().Should().Be("device_revoked", name);
        }
    }

    // TC-SYNC-NEW-1 (server half): A's clock is 1 h ahead → stored as T+5 min; 10 minutes later B (correct clock)
    // edits the same product and wins. The pull then hands phone A a row whose updatedAt (T+10) is OLDER than
    // A's own local edit (T+60), so phone A keeps showing its own value (see mobile qa_sync_test.dart).
    [Fact]
    public async Task TC_SYNC_NEW_1_server_takes_a_later_edit_over_a_clamped_future_edit()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var api = new ApiFactory(sql.ConnectionString,
            services: s => { s.RemoveAll<TimeProvider>(); s.AddSingleton<TimeProvider>(clock); });
        var a = await NewShop(api);
        var b = await Login(api, a);
        var id = Guid.CreateVersion7();
        var t = ZayPOS.Application.Sync.SyncJson.ToUtcMs(clock.Now.UtcDateTime);

        var ra = await PushOne(a, Unit("upsertProduct", new { products = new[] { Product(id, "A (clock +1h)", updatedAt: t.AddHours(1)) } }));
        ra.Issues.Should().Contain(SyncIssueKind.ClockSkew);

        clock.Now += TimeSpan.FromMinutes(10);
        var rb = await PushOne(b, Unit("upsertProduct", new { products = new[] { Product(id, "B (10 min later)", updatedAt: t.AddMinutes(10)) } }));
        rb.Outcome.Should().Be(UnitOutcome.Applied);

        await using var db = sql.CreateContext(a.TenantId);
        var p = await db.Products.SingleAsync(x => x.Id == id);
        p.Name.Should().Be("B (10 min later)", "B's edit is later than the clamped A edit (T+5)");
        p.UpdatedAt.Should().Be(t.AddMinutes(10));
        p.UpdatedAt.Should().BeBefore(t.AddHours(1), "phone A's local copy keeps updatedAt = T+60 and will not take this row");
    }
}
