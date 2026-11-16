using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;

namespace ZayPOS.Api.Tests.Zawgyi;

/// <summary>BUG-52 on the server: text typed with a Zawgyi keyboard is stored and pulled as Unicode.</summary>
[Collection(SqlServerCollection.Name)]
public class ZawgyiSyncTests(SqlServerFixture sql)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    [Fact]
    public async Task Register_stores_a_Zawgyi_shop_name_and_township_as_Unicode()
    {
        var (http, auth) = await Register(shopName: "ေရႊေစ်း ဆိုင္", township: "ႏွင္းဆီကုန္း");

        auth.Tenant.Name.Should().Be("ရွှေဈေး ဆိုင်");
        await using var db = sql.CreateContext(auth.Tenant.Id);
        var tenant = await db.Tenants.AsNoTracking().SingleAsync(t => t.Id == auth.Tenant.Id);
        tenant.Name.Should().Be("ရွှေဈေး ဆိုင်");
        tenant.Township.Should().Be("နှင်းဆီကုန်း");
        http.Dispose();
    }

    [Fact]
    public async Task A_Unicode_shop_name_is_stored_exactly_as_sent()
    {
        var (_, auth) = await Register(shopName: "ယခု မိုးရွာနေပါသလား။", township: null);
        auth.Tenant.Name.Should().Be("ယခု မိုးရွာနေပါသလား။", "the detector scores it 0.9997, but it is valid Unicode");
    }

    [Fact]
    public async Task Pushed_Zawgyi_customer_and_product_text_is_stored_and_pulled_as_Unicode()
    {
        var (http, auth) = await Register(shopName: "Zawgyi shop", township: null);
        var customerId = Guid.CreateVersion7();
        var productId = Guid.CreateVersion7();
        var t = SyncJson.ToUtcMs(DateTime.UtcNow);

        var customerUnit = Unit("upsertCustomer", new
        {
            customers = new[]
            {
                new
                {
                    id = customerId, name = "ေမာင္ေမာင္", phone = "09 790 011 152", address = "ျမန္မာ ႏိုင္ငံ",
                    note = "စကားခ်ီး", createdAt = t, updatedAt = t,
                },
            },
        });
        var productUnit = Unit("upsertProduct", new
        {
            products = new[]
            {
                new
                {
                    id = productId, name = "ေရႊ လက္ေကာက္", category = "ေက်ာက္မ်က္", unit = "ခု", barcode = "8850999150003",
                    cost = 1000, price = 1500, lowAlertMilli = 0, tint = 0, initial = "ေ", createdAt = t, updatedAt = t,
                },
            },
        });

        var results = await Push(http, auth, customerUnit, productUnit);
        results.Should().OnlyContain(r => r.Outcome == UnitOutcome.Applied);

        // Retry: still the same unit, answered from ProcessedUnits, nothing duplicated.
        (await Push(http, auth, customerUnit))[0].Outcome.Should().Be(UnitOutcome.Applied);

        var pull = await PullAll(http);
        var customer = pull.Changes.Customers.Single(c => c.Id == customerId);
        customer.Name.Should().Be("မောင်မောင်");
        customer.Address.Should().Be("မြန်မာ နိုင်ငံ");
        customer.Note.Should().Be("စကားချီး");
        customer.Phone.Should().Be("09 790 011 152");
        var product = pull.Changes.Products.Single(p => p.Id == productId);
        product.Name.Should().Be("ရွှေ လက်ကောက်");
        product.Category.Should().Be("ကျောက်မျက်");
        product.Unit.Should().Be("ခု");
        product.Barcode.Should().Be("8850999150003");

        await using var db = sql.CreateContext(auth.Tenant.Id);
        (await db.Customers.CountAsync(c => c.Id == customerId)).Should().Be(1);
        (await db.Customers.AsNoTracking().SingleAsync(c => c.Id == customerId)).Name.Should().Be("မောင်မောင်");
    }

    // ------------------------------------------------------------ helpers

    private async Task<(HttpClient Http, AuthResponse Auth)> Register(string shopName, string? township)
    {
        var http = sql.Api.CreateClient();
        var phone = "+9597" + Interlocked.Increment(ref _seq).ToString("D8");
        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var res = await http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(phone, sql.Api.Sms.LastCode(phone), shopName, "grocery", township, "123456",
                new DeviceInfo(Guid.CreateVersion7(), "A15")), Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return (http, auth);
    }

    private sealed record TestUnit(Guid UnitId, string Kind, DateTime ClientTime, object Rows);

    private static TestUnit Unit(string kind, object rows) =>
        new(Guid.CreateVersion7(), kind, SyncJson.ToUtcMs(DateTime.UtcNow), rows);

    private static async Task<List<UnitResult>> Push(HttpClient http, AuthResponse auth, params TestUnit[] units)
    {
        var res = await http.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = auth.Device.Id,
            units = units.Select(u => new { unitId = u.UnitId, kind = u.Kind, clientTime = u.ClientTime, rows = u.Rows }),
        }, Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var body = (await res.Content.ReadFromJsonAsync<PushResponse>(Json))!;
        body.Results.Where(r => r.Outcome != UnitOutcome.Applied).Should().BeEmpty(string.Join("; ", body.Results.Select(r => r.Reason)));
        return [.. body.Results];
    }

    private static async Task<PullResponse> PullAll(HttpClient http)
    {
        var res = await http.GetAsync("/api/v1/sync/pull?cursor=0&limit=1000");
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<PullResponse>(Json))!;
    }
}
