using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Account;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Catalog;
using ZayPOS.Application.Subscription;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Api.Tests;

/// <summary>STEP 4: /me, /catalog/presets, /devices, /subscription, /sync/limits.</summary>
[Collection(SqlServerCollection.Name)]
public class AccountTests(SqlServerFixture sql)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    // ================================================================ me

    [Fact]
    public async Task Me_returns_user_tenant_every_feature_flag_plan_and_devices()
    {
        var shop = await NewShop(sql.Api, "pharmacy");
        var second = await SecondDevice(sql.Api, shop);

        var me = await shop.Http.GetFromJsonAsync<MeResponse>("/api/v1/me", Json);

        me!.User.Id.Should().Be(shop.Auth.User.Id);
        me.User.Phone.Should().Be(shop.Phone);
        me.User.Role.Should().Be(UserRole.Owner);
        me.Tenant.Id.Should().Be(shop.TenantId);
        me.Tenant.TemplateId.Should().Be("pharmacy");
        me.Features.Keys.Should().BeEquivalentTo(FeatureKeys.All);
        me.Features.Should().Contain(ShopTemplates.FeaturesFor("pharmacy"));
        me.Plan.Should().Be(new PlanInfo(TenantPlan.Free, null, TenantPlan.Free));
        me.CurrentDeviceId.Should().Be(shop.DeviceId);
        me.Devices.Select(d => (d.Code, d.IsCurrent)).Should().Equal(("A", true), ("B", false));
        me.Devices[1].Id.Should().Be(second.DeviceId);
    }

    [Fact]
    public async Task Me_requires_a_token() =>
        (await sql.Api.CreateClient().GetAsync("/api/v1/me")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

    [Fact]
    public async Task Expired_pro_plan_is_active_free()
    {
        var shop = await NewShop(sql.Api);
        await using (var db = sql.CreateContext(shop.TenantId))
        {
            await db.Tenants.ExecuteUpdateAsync(s => s
                .SetProperty(t => t.Plan, TenantPlan.Pro).SetProperty(t => t.PlanExpiresAt, DateTime.UtcNow.AddDays(-1)));
        }

        var me = await shop.Http.GetFromJsonAsync<MeResponse>("/api/v1/me", Json);

        me!.Plan.Plan.Should().Be(TenantPlan.Pro);
        me.Plan.Active.Should().Be(TenantPlan.Free);
    }

    // ================================================================ presets

    [Fact]
    public async Task Grocery_presets_are_seeded_by_migration_and_served_in_order()
    {
        var shop = await NewShop(sql.Api);

        var catalog = await shop.Http.GetFromJsonAsync<PresetCatalog>("/api/v1/catalog/presets?template=grocery", Json);

        catalog!.Template.Should().Be("grocery");
        catalog.Items.Should().HaveCountGreaterThanOrEqualTo(20);
        catalog.Items.Select(i => i.SortOrder).Should().BeInAscendingOrder();
        catalog.Items.Should().OnlyContain(i => i.Name.Length > 0 && i.SuggestedPrice > 0 && i.Barcode == null);
        catalog.Items.Select(i => i.Category).Distinct().Should().BeSubsetOf(["စားသောက်ကုန်", "အချိုရည်", "အိမ်သုံး", "မုန့်"]);
        catalog.Items.Select(i => i.Unit).Distinct().Should().BeSubsetOf(["ခု", "ဗူး", "ပြည်", "ပိဿာ", "ထုပ်"]);
        catalog.Items.Should().OnlyContain(i =>
            i.Name.Length <= SyncLimits.ProductName.MaxLength && i.Category.Length <= SyncLimits.ProductCategory.MaxLength
            && i.Unit.Length <= SyncLimits.ProductUnit.MaxLength, "a preset becomes a product the app pushes back");
    }

    [Fact]
    public async Task Presets_have_an_etag_and_answer_304_when_unchanged()
    {
        var shop = await NewShop(sql.Api);
        var first = await shop.Http.GetAsync("/api/v1/catalog/presets?template=grocery");
        first.StatusCode.Should().Be(HttpStatusCode.OK);
        var etag = first.Headers.ETag;
        etag.Should().NotBeNull();
        etag!.IsWeak.Should().BeFalse();

        using var revalidate = new HttpRequestMessage(HttpMethod.Get, "/api/v1/catalog/presets?template=grocery");
        revalidate.Headers.IfNoneMatch.Add(etag);
        var second = await shop.Http.SendAsync(revalidate);

        second.StatusCode.Should().Be(HttpStatusCode.NotModified);
        second.Headers.ETag.Should().Be(etag);
        (await second.Content.ReadAsByteArrayAsync()).Should().BeEmpty();
    }

    [Fact]
    public async Task Presets_default_to_the_shops_template_and_reject_unknown_ones()
    {
        var phoneShop = await NewShop(sql.Api, "phone");

        var mine = await phoneShop.Http.GetFromJsonAsync<PresetCatalog>("/api/v1/catalog/presets", Json);
        var unknown = await phoneShop.Http.GetAsync("/api/v1/catalog/presets?template=bakery");

        mine!.Template.Should().Be("phone");
        mine.Items.Should().BeEmpty("only grocery has sample presets so far");
        unknown.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    // ================================================================ devices

    [Fact]
    public async Task Owner_revokes_a_lost_phone_which_then_cannot_sync_refresh_or_read()
    {
        var shop = await NewShop(sql.Api);
        var lost = await SecondDevice(sql.Api, shop);

        var revoke = await shop.Http.DeleteAsync($"/api/v1/devices/{lost.DeviceId}");
        var again = await shop.Http.DeleteAsync($"/api/v1/devices/{lost.DeviceId}");

        revoke.StatusCode.Should().Be(HttpStatusCode.NoContent);
        again.StatusCode.Should().Be(HttpStatusCode.NoContent, "revoking is idempotent");
        var devices = await shop.Http.GetFromJsonAsync<List<DeviceInfoDto>>("/api/v1/devices", Json);
        devices!.Select(d => d.Id).Should().Equal(shop.DeviceId);

        // Its access token is still unexpired, but every endpoint refuses it…
        (await lost.Http.GetAsync("/api/v1/me")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await lost.Http.GetAsync("/api/v1/sync/pull")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        // …and its refresh token is dead.
        var refresh = await sql.Api.CreateClient().PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(lost.Auth.RefreshToken), Json);
        refresh.IsSuccessStatusCode.Should().BeFalse();

        // The other phones learn about it through pull (soft delete).
        var pull = await shop.Http.GetFromJsonAsync<PullResponse>("/api/v1/sync/pull?cursor=0", Json);
        pull!.Changes.Devices.Single(d => d.Id == lost.DeviceId).DeletedAt.Should().NotBeNull();
    }

    [Fact]
    public async Task A_device_cannot_revoke_itself_or_another_shops_device()
    {
        var shop = await NewShop(sql.Api);
        var other = await NewShop(sql.Api);

        (await shop.Http.DeleteAsync($"/api/v1/devices/{shop.DeviceId}")).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await shop.Http.DeleteAsync($"/api/v1/devices/{other.DeviceId}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        await using var db = sql.CreateContext(other.TenantId);
        (await db.Devices.SingleAsync()).DeletedAt.Should().BeNull();
    }

    // ================================================================ sync limits

    [Fact]
    public async Task Sync_limits_are_public_and_match_what_the_validator_enforces()
    {
        var res = await sql.Api.CreateClient().GetAsync("/api/v1/sync/limits");
        res.StatusCode.Should().Be(HttpStatusCode.OK);
        var limits = (await res.Content.ReadFromJsonAsync<SyncLimitsResponse>(Json))!;

        limits.MaxUnitsPerPush.Should().Be(SyncLimits.MaxUnitsPerPush);
        limits.PullDefaultLimit.Should().Be(SyncLimits.PullDefaultLimit);
        limits.MaxClockAheadSeconds.Should().Be(300);
        limits.Text.Should().HaveCount(SyncLimits.Texts.Count);
        limits.Text["products.name"].MaxLength.Should().Be(150);
        limits.Text["sales.no"].NonAscii.Should().Be(NonAsciiRule.Reject);
        limits.Numbers["saleLines.qtyMilli"].Min.Should().Be(1);
        (await res.Content.ReadAsStringAsync()).Should().Contain("\"products.name\"", "keys are the wire field names");
    }

    [Fact]
    public async Task A_name_one_over_the_published_limit_is_rejected_and_at_the_limit_is_applied()
    {
        var shop = await NewShop(sql.Api);
        var max = SyncLimits.ProductName.MaxLength;

        var ok = await PushProduct(shop, new string('က', max));
        var tooLong = await PushProduct(shop, new string('က', max + 1));

        ok.Outcome.Should().Be(UnitOutcome.Applied);
        tooLong.Outcome.Should().Be(UnitOutcome.Rejected);
        tooLong.Reason.Should().Be($"products.name is longer than {max} characters.");
    }

    [Fact]
    public void Every_limit_field_name_is_unique() =>
        SyncLimits.Texts.Select(t => t.Field).Concat(SyncLimits.Numbers.Select(n => n.Field)).Should().OnlyHaveUniqueItems();

    // ================================================================ subscription

    [Fact]
    public async Task Owner_uploads_a_screenshot_then_records_a_pending_payment_once()
    {
        var (api, storage) = WithFakeStorage();
        await using var host = api;
        var shop = await NewShop(api);

        var upload = await Post<PresignedUpload>(shop, "/api/v1/subscription/screenshot-url", new ScreenshotUrlRequest("image/jpeg", 200_000));
        upload.Key.Should().StartWith($"subscriptions/{shop.TenantId:N}/").And.EndWith(".jpg");
        upload.Method.Should().Be("PUT");
        storage.Uploaded.Add(upload.Key); // the app PUTs the bytes to upload.Url

        var request = new CreateSubscriptionPayment(Guid.CreateVersion7(), PaymentMethod.Kbz, 12, 150_000, upload.Key);
        var created = await shop.Http.PostAsJsonAsync("/api/v1/subscription/payments", request, Json);
        var retried = await shop.Http.PostAsJsonAsync("/api/v1/subscription/payments", request, Json);

        created.StatusCode.Should().Be(HttpStatusCode.Created);
        retried.StatusCode.Should().Be(HttpStatusCode.OK, "same id = the same payment");
        var sub = await shop.Http.GetFromJsonAsync<SubscriptionResponse>("/api/v1/subscription", Json);
        sub!.Payments.Should().ContainSingle().Which.Should().Match<SubscriptionPaymentDto>(p =>
            p.Id == request.Id && p.Status == SubscriptionStatus.Pending && p.Amount == 150_000 && p.Months == 12);
        sub.Plan.Active.Should().Be(TenantPlan.Free, "an admin approves it later");
        sub.Prices.Should().ContainSingle(p => p.Months == 12 && p.Amount == 150_000);
        sub.PayTo.Should().ContainKey("kbz");

        var second = await shop.Http.PostAsJsonAsync("/api/v1/subscription/payments",
            request with { Id = Guid.CreateVersion7() }, Json);
        second.StatusCode.Should().Be(HttpStatusCode.Conflict, "one payment waits for review at a time");
    }

    [Fact]
    public async Task Payment_needs_an_uploaded_screenshot_of_its_own_shop_and_valid_fields()
    {
        var (api, storage) = WithFakeStorage();
        await using var host = api;
        var shop = await NewShop(api);
        var other = await NewShop(api);
        var foreignKey = $"subscriptions/{other.TenantId:N}/{Guid.CreateVersion7():N}.jpg";
        var notUploaded = $"subscriptions/{shop.TenantId:N}/{Guid.CreateVersion7():N}.jpg";
        var uploaded = $"subscriptions/{shop.TenantId:N}/{Guid.CreateVersion7():N}.png";
        storage.Uploaded.Add(foreignKey);
        storage.Uploaded.Add(uploaded);

        async Task<string?> Code(CreateSubscriptionPayment p)
        {
            var res = await shop.Http.PostAsJsonAsync("/api/v1/subscription/payments", p, Json);
            return res.IsSuccessStatusCode ? null : (await res.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString();
        }
        var good = new CreateSubscriptionPayment(Guid.CreateVersion7(), PaymentMethod.Wave, 1, 15_000, uploaded);

        (await Code(good with { ScreenshotKey = foreignKey })).Should().Be("validation");
        (await Code(good with { ScreenshotKey = "../" + uploaded })).Should().Be("validation");
        (await Code(good with { ScreenshotKey = notUploaded })).Should().Be("screenshot_missing");
        (await Code(good with { Method = PaymentMethod.Cash })).Should().Be("validation");
        (await Code(good with { Months = 6 })).Should().Be("validation");
        (await Code(good with { Amount = 0 })).Should().Be("validation");
        (await Code(good)).Should().BeNull();
    }

    [Fact]
    public async Task Screenshot_url_only_for_small_images()
    {
        var (api, _) = WithFakeStorage();
        await using var host = api;
        var shop = await NewShop(api);

        (await shop.Http.PostAsJsonAsync("/api/v1/subscription/screenshot-url", new ScreenshotUrlRequest("application/pdf", 1000), Json))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await shop.Http.PostAsJsonAsync("/api/v1/subscription/screenshot-url",
                new ScreenshotUrlRequest("image/png", SubscriptionService.MaxScreenshotBytes + 1), Json))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Without_R2_config_screenshot_upload_answers_503()
    {
        var shop = await NewShop(sql.Api);
        var res = await shop.Http.PostAsJsonAsync("/api/v1/subscription/screenshot-url", new ScreenshotUrlRequest("image/png", 1000), Json);
        res.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
        (await res.Content.ReadAsStringAsync()).Should().Contain("storage_not_configured");
    }

    [Fact]
    public async Task With_R2_config_the_upload_url_is_a_presigned_put_bound_to_type_and_size()
    {
        await using var api = new ApiFactory(sql.ConnectionString, settings: new Dictionary<string, string?>
        {
            ["Storage:R2:AccountId"] = "acc123",
            ["Storage:R2:AccessKeyId"] = "AKIDTEST",
            ["Storage:R2:SecretAccessKey"] = "secret-test",
            ["Storage:R2:Bucket"] = "zaypos-screens",
        });
        var shop = await NewShop(api);

        var upload = await Post<PresignedUpload>(shop, "/api/v1/subscription/screenshot-url", new ScreenshotUrlRequest("image/png", 4321));

        upload.Url.Host.Should().Be("acc123.r2.cloudflarestorage.com");
        upload.Url.AbsolutePath.Should().Be($"/zaypos-screens/{upload.Key}");
        var query = upload.Url.Query;
        query.Should().Contain("X-Amz-Algorithm=AWS4-HMAC-SHA256")
            .And.Contain("%2Fauto%2Fs3%2Faws4_request")
            .And.Contain("X-Amz-Expires=600")
            .And.Contain("X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost")
            .And.MatchRegex("X-Amz-Signature=[0-9a-f]{64}$");
        upload.Headers.Should().Contain("Content-Type", "image/png").And.Contain("Content-Length", "4321");
        upload.ExpiresAt.Should().BeCloseTo(DateTime.UtcNow.AddMinutes(10), TimeSpan.FromMinutes(1));
    }

    // ================================================================ helpers

    private sealed record Shop(HttpClient Http, AuthResponse Auth, string Phone)
    {
        public Guid TenantId => Auth.Tenant.Id;
        public Guid DeviceId => Auth.Device.Id;
    }

    private sealed class FakeStorage : IFileStorage
    {
        public ConcurrentBag<string> Uploaded { get; } = [];

        public PresignedUpload PresignUpload(string key, string contentType, long sizeBytes, TimeSpan validFor) =>
            new(key, new Uri($"https://storage.test/{key}"), "PUT", new Dictionary<string, string> { ["Content-Type"] = contentType },
                DateTime.UtcNow.Add(validFor));

        public Uri PresignDownload(string key, TimeSpan validFor) => new($"https://storage.test/{key}");

        public Task<bool> ExistsAsync(string key, CancellationToken ct) => Task.FromResult(Uploaded.Contains(key));
    }

    /// <summary>A separate host per test: its storage fake and subscription config are its own.</summary>
    private (ApiFactory Api, FakeStorage Storage) WithFakeStorage()
    {
        var storage = new FakeStorage();
        var api = new ApiFactory(sql.ConnectionString,
            services: s =>
            {
                s.RemoveAll<IFileStorage>();
                s.AddSingleton<IFileStorage>(storage);
            },
            settings: new Dictionary<string, string?>
            {
                ["Subscription:Prices:0:Months"] = "12",
                ["Subscription:Prices:0:Amount"] = "150000",
                ["Subscription:PayTo:kbz"] = "09-000000000",
            });
        return (api, storage);
    }

    private static async Task<T> Post<T>(Shop shop, string url, object body)
    {
        var res = await shop.Http.PostAsJsonAsync(url, body, Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<T>(Json))!;
    }

    private static async Task<UnitResult> PushProduct(Shop shop, string name)
    {
        var now = DateTime.UtcNow;
        var body = new
        {
            deviceId = shop.DeviceId,
            units = new[]
            {
                new
                {
                    unitId = Guid.CreateVersion7(), kind = "upsertProduct", clientTime = now,
                    rows = new
                    {
                        products = new[]
                        {
                            new
                            {
                                id = Guid.CreateVersion7(), name, category = "မုန့်", unit = "ခု", cost = 100, price = 200,
                                lowAlertMilli = 0, tint = 0, initial = "က", createdAt = now, updatedAt = now,
                            },
                        },
                    },
                },
            },
        };
        var res = await shop.Http.PostAsJsonAsync("/api/v1/sync/push", body, Json);
        res.EnsureSuccessStatusCode();
        return (await res.Content.ReadFromJsonAsync<PushResponse>(Json))!.Results.Single();
    }

    private static async Task<Shop> NewShop(ApiFactory api, string template = "grocery")
    {
        var http = api.CreateClient();
        var phone = "+9597" + Interlocked.Increment(ref _seq).ToString("D8");
        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var res = await http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(phone, api.Sms.LastCode(phone), "Account shop", template, null, "123456",
                new DeviceInfo(Guid.CreateVersion7(), "A15")), Json);
        res.EnsureSuccessStatusCode();
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new Shop(http, auth, phone);
    }

    private static async Task<Shop> SecondDevice(ApiFactory api, Shop shop)
    {
        var http = api.CreateClient();
        var res = await http.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(shop.Phone, "123456", new DeviceInfo(Guid.CreateVersion7(), "Redmi")), Json);
        res.EnsureSuccessStatusCode();
        var auth = (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return new Shop(http, auth, shop.Phone);
    }
}
