using System.Text.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>QA round 2 — server halves of the BUG-1 / BUG-4 / BUG-5 fixes (real API + SQL Server).</summary>
[Collection(QaSqlCollection.Name)]
public class QaRound2Tests(SqlServerFixture sql)
{
    private static object Debt(Guid id, Guid customer, string type, long amount, string? method, string? note = null, DateTime? at = null)
    {
        var t = at ?? Now();
        return new { id, customerId = customer, type, amount, method, note, createdAt = t, updatedAt = t };
    }

    private static object PayDebt(params object[] entries) => Unit("payDebt", new { debtEntries = entries });

    // TC-DEBT-NEW-4 (server half): phone A and phone B both reverse the same wrong payment while offline.
    // The app derives the reversal id from the payment id (paymentReversalId, UUID v5), so both phones push an
    // adjustment row with the SAME id but their own createdAt / deviceId. Expected: both units are applied (B's
    // outbox is not blocked), the server keeps ONE reversal, and the balance is back to what it was before the
    // wrong payment — once.
    [Fact]
    public async Task TC_DEBT_NEW_4_two_phones_reversing_one_payment_offline_keep_one_reversal()
    {
        var a = await NewShop(sql.Api);
        var b = await Login(sql.Api, a);
        var customer = await AddCustomer(a);
        (await PushOne(a, Unit("upsertCustomer", new { debtEntries = new[] { Debt(Guid.CreateVersion7(), customer, "adjustment", 52_000, null, "ယခင်အကြွေး") } })))
            .Outcome.Should().Be(UnitOutcome.Applied);
        var payment = Guid.CreateVersion7();
        (await PushOne(a, PayDebt(Debt(payment, customer, "payment", 20_000, "kbz")))).Outcome.Should().Be(UnitOutcome.Applied);

        var reversalId = Guid.NewGuid(); // stands for paymentReversalId(payment): identical on both phones
        var ra = await PushOne(a, PayDebt(Debt(reversalId, customer, "adjustment", 20_000, "kbz", "ငွေပြန်ဆပ် ပြန်ပယ် · KBZPay", Now())));
        var rb = await PushOne(b, PayDebt(Debt(reversalId, customer, "adjustment", 20_000, "kbz", "ငွေပြန်ဆပ် ပြန်ပယ် · KBZPay", Now().AddSeconds(3))));

        ra.Outcome.Should().Be(UnitOutcome.Applied);
        rb.Outcome.Should().NotBe(UnitOutcome.Rejected, "a rejected unit would block phone B's outbox (TC-SYNC-11)");
        await using var db = sql.CreateContext(a.TenantId);
        var entries = await db.DebtEntries.Where(e => e.CustomerId == customer).ToListAsync();
        entries.Count(e => e.Id == reversalId).Should().Be(1, "insert-only: the second reversal is the same row");
        entries.Single(e => e.Id == payment).DeletedAt.Should().BeNull("the wrong payment is never deleted");
        entries.Sum(e => e.Effect).Should().Be(52_000, "52,000 − 20,000 (wrong payment) + 20,000 (reversal, once)");

        // Phone B pulls: exactly one reversal row with that id comes down (the phone replaces its own copy by id).
        var pulled = (await PullAllPages(b))
            .SelectMany(p => p.GetProperty("changes").GetProperty("debtEntries").EnumerateArray())
            .Where(r => r.GetProperty("id").GetGuid() == reversalId).ToList();
        pulled.Should().HaveCount(1);
        pulled[0].GetProperty("amount").GetInt64().Should().Be(20_000);
    }

    // TC-SYNC-NEW-2 (server half): the phone clamps its own edit times to the push answer's serverTime (BUG-5),
    // so serverTime must be in the answer, in UTC, and be the server's clock (not the phone's clientTime).
    [Fact]
    public async Task TC_SYNC_NEW_2_push_answer_carries_the_server_clock_in_utc()
    {
        // Real "now" (JWT lifetime is checked against the real clock), whole milliseconds like the wire format.
        var serverNow = new DateTimeOffset(SyncJson.ToUtcMs(DateTime.UtcNow), TimeSpan.Zero);
        var clock = new ManualClock(serverNow);
        await using var api = new ApiFactory(sql.ConnectionString,
            services: s => { s.RemoveAll<TimeProvider>(); s.AddSingleton<TimeProvider>(clock); });
        var a = await NewShop(api);
        var id = Guid.CreateVersion7();
        var phoneAhead = serverNow.UtcDateTime.AddHours(1);

        var res = await a.Http.PostAsync("/api/v1/sync/push", new StringContent(JsonSerializer.Serialize(new
        {
            deviceId = a.DeviceId,
            units = new[] { new { unitId = Guid.CreateVersion7(), kind = "upsertProduct", clientTime = phoneAhead,
                rows = new { products = new[] { Product(id, "A (clock +1h)", updatedAt: phoneAhead) } } } },
        }, Json), System.Text.Encoding.UTF8, "application/json"));
        var body = await res.Content.ReadAsStringAsync();
        res.IsSuccessStatusCode.Should().BeTrue(body);

        var raw = JsonDocument.Parse(body).RootElement.GetProperty("serverTime").GetString()!;
        raw.Should().EndWith("Z", "the phone parses it with DateTime.tryParse; without a zone it would be read as phone-local time");
        DateTime.Parse(raw, null, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime()
            .Should().Be(serverNow.UtcDateTime, "serverTime is the server's clock, not the phone's");

        await using var db = sql.CreateContext(a.TenantId);
        (await db.Products.SingleAsync(p => p.Id == id)).UpdatedAt.Should().Be(serverNow.UtcDateTime.AddMinutes(5),
            "the server stored serverTime + 5 min — the value the phone must clamp its copy to");
    }

    // TC-PROD-NEW-3 (server half): the edit form sends the whole product row again with a later updatedAt and the
    // same createdAt (one upsertProduct unit). The server takes the new name / prices; stock is not touched.
    [Fact]
    public async Task TC_PROD_NEW_3_an_edited_product_row_replaces_the_old_one_and_keeps_stock()
    {
        var a = await NewShop(sql.Api);
        var id = await AddProduct(a, 12_000, "ရေသန့် 1L");
        await using (var db0 = sql.CreateContext(a.TenantId))
        {
            var before = await db0.Products.SingleAsync(p => p.Id == id);
            var edited = new
            {
                id, name = "ရေသန့် 1 လီတာ", category = "General", unit = "ဗူး", cost = 500L, price = 700L, lowAlertMilli = 2500,
                tint = 0, initial = "ရ", createdAt = before.CreatedAt, updatedAt = Now().AddSeconds(1),
            };
            (await PushOne(a, Unit("upsertProduct", new { products = new[] { edited } }))).Outcome.Should().Be(UnitOutcome.Applied);
        }

        await using var db = sql.CreateContext(a.TenantId);
        var p = await db.Products.SingleAsync(x => x.Id == id);
        (p.Name, p.Price, p.Cost, p.LowAlertMilli).Should().Be(("ရေသန့် 1 လီတာ", 700L, 500L, 2500L));
        (await db.StockMovements.Where(m => m.ProductId == id).SumAsync(m => m.QtyMilli)).Should().Be(12_000);
    }
}
