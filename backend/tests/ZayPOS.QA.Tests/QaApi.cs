using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;

namespace ZayPOS.QA.Tests;

/// <summary>Own collection: one throw-away SQL Server container for the QA assembly.</summary>
[CollectionDefinition(Name)]
public sealed class QaSqlCollection : ICollectionFixture<SqlServerFixture>
{
    public const string Name = "qa-sqlserver";
}

/// <summary>A clock the test moves by hand (OTP expiry).</summary>
public sealed class ManualClock(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;
    public override DateTimeOffset GetUtcNow() => Now;
}

public sealed record QaShop(HttpClient Http, AuthResponse Auth, string Phone)
{
    public Guid TenantId => Auth.Tenant.Id;
    public Guid DeviceId => Auth.Device.Id;
}

/// <summary>Small HTTP helpers shared by the QA tests (black-box: only the public API).</summary>
public static class QaApi
{
    public const string Pin = "123456";

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    public static string NewPhone() => "+9598" + Interlocked.Increment(ref _seq).ToString("D8");

    public static async Task<QaShop> NewShop(ApiFactory api, string template = "grocery", string? phone = null)
    {
        var http = api.CreateClient();
        phone ??= NewPhone();
        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var res = await http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(phone, api.Sms.LastCode(phone), "QA shop", template, null, Pin,
                new DeviceInfo(Guid.CreateVersion7(), "QA A")), Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new QaShop(http, auth, phone);
    }

    public static async Task<QaShop> Login(ApiFactory api, QaShop shop, Guid? deviceId = null)
    {
        var http = api.CreateClient();
        var res = await http.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(shop.Phone, Pin, new DeviceInfo(deviceId ?? Guid.CreateVersion7(), "QA other")), Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new QaShop(http, auth, shop.Phone);
    }

    public static DateTime Now() => SyncJson.ToUtcMs(DateTime.UtcNow);

    public static object Unit(string kind, object rows, Guid? unitId = null) =>
        new { unitId = unitId ?? Guid.CreateVersion7(), kind, clientTime = Now(), rows };

    public static async Task<List<UnitResult>> Push(QaShop shop, params object[] units)
    {
        var res = await shop.Http.PostAsJsonAsync("/api/v1/sync/push", new { deviceId = shop.DeviceId, units }, Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return [.. (await res.Content.ReadFromJsonAsync<PushResponse>(Json))!.Results];
    }

    public static async Task<UnitResult> PushOne(QaShop shop, object unit) => (await Push(shop, unit))[0];

    public static object Product(Guid id, string name = "QA product", long price = 600, long cost = 450, string? barcode = null,
        DateTime? updatedAt = null, Guid? tenantId = null)
    {
        var t = updatedAt ?? Now();
        return new
        {
            id, tenantId, name, category = "General", unit = "ဗူး", barcode, cost, price, lowAlertMilli = 5000,
            tint = 0, initial = "Q", createdAt = t, updatedAt = t,
        };
    }

    public static async Task<Guid> AddProduct(QaShop shop, long stockMilli = 0, string name = "QA product")
    {
        var id = Guid.CreateVersion7();
        var t = Now();
        object rows = stockMilli == 0
            ? new { products = new[] { Product(id, name) } }
            : new
            {
                products = new[] { Product(id, name) },
                stockMovements = new[] { new { id = Guid.CreateVersion7(), productId = id, type = "restock", qtyMilli = stockMilli, createdAt = t, updatedAt = t } },
            };
        (await PushOne(shop, Unit("upsertProduct", rows))).Outcome.Should().Be(UnitOutcome.Applied);
        return id;
    }

    public static async Task<Guid> AddCustomer(QaShop shop, long? creditLimit = null)
    {
        var id = Guid.CreateVersion7();
        var t = Now();
        (await PushOne(shop, Unit("upsertCustomer", new
        {
            customers = new[] { new { id, name = "QA customer", phone = "09123456789", creditLimit, createdAt = t, updatedAt = t } },
        }))).Outcome.Should().Be(UnitOutcome.Applied);
        return id;
    }

    /// <summary>A checkout unit (one line) in the wire shape the app sends.</summary>
    public static (object Unit, Guid SaleId) Checkout(QaShop shop, string no, Guid? product, long qtyMilli, long price,
        string method = "cash", Guid? customer = null, long? clientTotal = null, long? clientLineTotal = null)
    {
        var t = Now();
        var saleId = Guid.CreateVersion7();
        var lineTotal = Ledger.LineTotal(price, qtyMilli);
        var movements = product is null
            ? Array.Empty<object>()
            : [new { id = Guid.CreateVersion7(), productId = product, type = "sale", qtyMilli = -qtyMilli, saleId, createdAt = t, updatedAt = t }];
        var payments = method == "debt"
            ? Array.Empty<object>()
            : [new { id = Guid.CreateVersion7(), saleId, method, amount = lineTotal, received = lineTotal, createdAt = t, updatedAt = t }];
        var debts = method == "debt"
            ? new object[] { new { id = Guid.CreateVersion7(), customerId = customer, type = "creditSale", amount = lineTotal, saleId, saleNo = no, createdAt = t, updatedAt = t } }
            : [];
        var unit = Unit("checkout", new
        {
            sales = new[] { new { id = saleId, no, method, customerId = customer, total = clientTotal ?? lineTotal, createdAt = t, updatedAt = t } },
            saleLines = new[]
            {
                new { id = Guid.CreateVersion7(), saleId, productId = product, name = "line", qtyMilli, price, costSnapshot = price / 2,
                      lineTotal = clientLineTotal ?? lineTotal, createdAt = t, updatedAt = t },
            },
            payments,
            stockMovements = movements,
            debtEntries = debts,
        });
        return (unit, saleId);
    }

    /// <summary>Raw pull from a cursor (all pages).</summary>
    public static async Task<List<JsonElement>> PullAllPages(QaShop shop, string cursor = "0")
    {
        var pages = new List<JsonElement>();
        while (true)
        {
            var res = await shop.Http.GetAsync($"/api/v1/sync/pull?cursor={cursor}&limit=1000");
            res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
            var page = JsonDocument.Parse(await res.Content.ReadAsStringAsync()).RootElement.Clone();
            pages.Add(page);
            cursor = page.GetProperty("cursor").GetString()!;
            if (!page.GetProperty("hasMore").GetBoolean()) return pages;
        }
    }

    public static async Task<JsonElement> Problem(HttpResponseMessage res)
    {
        var body = await res.Content.ReadAsStringAsync();
        return JsonDocument.Parse(body).RootElement.Clone();
    }
}
