using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Account;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Api.Tests;

/// <summary>docs/backend/auth-google.md §3–4, end to end with the fake Google verifier and OTP OFF.</summary>
[Collection(SqlServerCollection.Name)]
public class GoogleAuthTests : IAsyncLifetime
{
    private const string Pin = "123456";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _phoneSeq = Random.Shared.Next(1_000_000, 9_000_000);

    private readonly SqlServerFixture _sql;
    private readonly ApiFactory _api;
    private readonly HttpClient _http;

    public GoogleAuthTests(SqlServerFixture sql)
    {
        _sql = sql;
        _api = new ApiFactory(sql.ConnectionString, settings: new Dictionary<string, string?> { ["Auth:OtpEnabled"] = "false" });
        _http = _api.CreateClient();
    }

    public Task InitializeAsync() => Task.CompletedTask;
    public async Task DisposeAsync() => await _api.DisposeAsync();

    // ------------------------------------------------------------ who is this user

    [Fact]
    public async Task A_new_google_account_has_no_shops()
    {
        var shops = await Shops(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject(), "new@gmail.com"));

        shops.Email.Should().Be("new@gmail.com");
        shops.Shops.Should().BeEmpty();
    }

    [Theory]
    [InlineData("bad", HttpStatusCode.Unauthorized, "google_token_invalid")]
    [InlineData("down", HttpStatusCode.ServiceUnavailable, "google_unavailable")]
    public async Task Every_google_endpoint_refuses_a_bad_token_before_doing_anything(string token, HttpStatusCode status, string code)
    {
        var device = new DeviceInfo(Guid.CreateVersion7(), null);
        await ShouldBeProblem(await Post("/api/v1/auth/google/shops", new GoogleShopsRequest(token)), status, code);
        await ShouldBeProblem(await Post("/api/v1/auth/google", new GoogleSignInRequest(token, Guid.NewGuid(), Pin, device)), status, code);
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token)), status, code);
        await ShouldBeProblem(await Post("/api/v1/auth/google/pin/reset", new GoogleResetPinRequest(token, Guid.NewGuid(), Pin)), status, code);
    }

    // ------------------------------------------------------------ register (create)

    [Fact]
    public async Task Register_creates_the_shop_owned_by_the_google_account_with_device_A()
    {
        var sub = FakeGoogleVerifier.NewSubject();
        var ownerPhone = NewPhone();
        var deviceId = Guid.CreateVersion7();

        var auth = await Register(FakeGoogleVerifier.Token(sub, "shop@gmail.com"), template: "pharmacy",
            ownerPhone: "09 7" + ownerPhone[5..], deviceId: deviceId);

        auth.Device.Should().Be(new AuthDevice(deviceId, "A", 0));
        auth.User.Role.Should().Be(UserRole.Owner);
        auth.Tenant.TemplateId.Should().Be("pharmacy");

        await using var db = _sql.CreateContext(auth.Tenant.Id);
        var user = await db.Users.SingleAsync();
        user.GoogleSubject.Should().Be(sub);
        user.GoogleEmail.Should().Be("shop@gmail.com");
        user.Phone.Should().BeNull("the owner phone is an unverified contact, never a login phone");
        (await db.Tenants.SingleAsync()).Phone.Should().Be(ownerPhone, "normalized to E.164 on the tenant");
        (await db.TenantFeatures.ToDictionaryAsync(f => f.FeatureKey, f => f.Enabled))
            .Should().BeEquivalentTo(ShopTemplates.FeaturesFor("pharmacy"));

        // The access token works on the API like any other.
        var me = await Me(auth);
        me.User.Phone.Should().BeNull();
        me.User.GoogleEmail.Should().Be("shop@gmail.com");
        me.Tenant.Phone.Should().Be(ownerPhone);
    }

    [Fact]
    public async Task Two_google_shops_may_give_the_same_unverified_owner_phone()
    {
        var phone = NewPhone();
        var first = await Register(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()), ownerPhone: phone);
        var second = await Register(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()), ownerPhone: phone);

        (await Me(first)).Tenant.Phone.Should().Be(phone);
        (await Me(second)).Tenant.Phone.Should().Be(phone);
    }

    [Fact]
    public async Task There_is_no_phone_and_PIN_sign_in_on_a_new_phone()
    {
        // Not for a Google shop's owner phone, and not even for a verified phone with the right PIN.
        var owner = NewPhone();
        await Register(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()), ownerPhone: owner);
        var verified = NewPhone();
        await RegisterByOtp(verified);

        foreach (var phone in new[] { owner, verified })
        {
            var res = await Post("/api/v1/auth/login", new { phone, pin = Pin, device = new DeviceInfo(Guid.CreateVersion7(), null) });
            res.StatusCode.Should().Be(HttpStatusCode.NotFound, "POST /auth/login no longer exists");
        }
    }

    [Fact]
    public async Task Register_validates_before_asking_google()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var before = _api.Google.Calls;
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token, ownerPhone: "12345")), HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token, ownerPhone: "")), HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token, template: "bakery")), HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token, pin: "1234")), HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token, shopName: " ")), HttpStatusCode.BadRequest, "validation");
        _api.Google.Calls.Should().Be(before);
    }

    [Fact]
    public async Task One_google_account_can_own_several_shops_up_to_the_limit()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var names = new List<string>();
        for (var i = 0; i < AuthRules.GoogleShopsPerAccount; i++)
        {
            names.Add($"ဆိုင် {i}");
            await Register(token, shopName: names[^1]);
        }

        (await Shops(token)).Shops.Select(s => s.Name).Should().Equal(names, "oldest first");
        await ShouldBeProblem(await Post("/api/v1/auth/google/register", RegisterBody(token)), HttpStatusCode.Conflict, "google_shop_limit");
    }

    [Fact]
    public async Task Register_with_a_device_id_of_another_shop_is_a_device_conflict()
    {
        var first = await Register(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()));
        await ShouldBeProblem(
            await Post("/api/v1/auth/google/register", RegisterBody(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()), deviceId: first.Device.Id)),
            HttpStatusCode.Conflict, "device_conflict");
    }

    // ------------------------------------------------------------ sign in (find)

    [Fact]
    public async Task A_new_phone_signs_in_by_choosing_the_shop_and_entering_the_PIN_and_gets_device_B()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var a = await Register(token, shopName: "ရွှေဝါ");

        var shops = await Shops(token);
        shops.Shops.Should().ContainSingle().Which.Should().Be(new GoogleShop(a.Tenant.Id, "ရွှေဝါ", "grocery", UserRole.Owner));

        var deviceB = Guid.CreateVersion7();
        var b = await SignInOk(token, a.Tenant.Id, Pin, deviceB);

        b.Tenant.Id.Should().Be(a.Tenant.Id);
        b.User.Id.Should().Be(a.User.Id);
        b.Device.Should().Be(new AuthDevice(deviceB, "B", 0));
        (await Me(b)).CurrentDeviceId.Should().Be(deviceB);

        // The same phone signing in again keeps its code and ends its old session only.
        var b2 = await SignInOk(token, a.Tenant.Id, Pin, deviceB);
        b2.Device.Code.Should().Be("B");
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(b.RefreshToken)), HttpStatusCode.Unauthorized, "invalid_refresh_token");
        (await Post("/api/v1/auth/refresh", new RefreshRequest(a.RefreshToken))).StatusCode.Should().Be(HttpStatusCode.OK, "device A is untouched");
    }

    [Fact]
    public async Task Sign_in_to_a_shop_of_another_google_account_is_shop_not_found()
    {
        var theirs = await Register(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()));
        var mine = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());

        await ShouldBeProblem(await SignIn(mine, theirs.Tenant.Id, Pin, Guid.CreateVersion7()), HttpStatusCode.NotFound, "shop_not_found");
        await ShouldBeProblem(await SignIn(mine, Guid.NewGuid(), Pin, Guid.CreateVersion7()), HttpStatusCode.NotFound, "shop_not_found");
        await ShouldBeProblem(await Post("/api/v1/auth/google/pin/reset", new GoogleResetPinRequest(mine, theirs.Tenant.Id, "654321")),
            HttpStatusCode.NotFound, "shop_not_found");
    }

    [Fact]
    public async Task Five_wrong_pins_lock_the_google_user_for_15_minutes_like_phone_login()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var a = await Register(token);
        var device = Guid.CreateVersion7();

        for (var i = 0; i < 4; i++)
            await ShouldBeProblem(await SignIn(token, a.Tenant.Id, "999999", device), HttpStatusCode.Unauthorized, "invalid_credentials");
        var fifth = await SignIn(token, a.Tenant.Id, "999999", device);
        await ShouldBeProblem(fifth, HttpStatusCode.Locked, "pin_locked");
        fifth.Headers.RetryAfter!.Delta.Should().Be(TimeSpan.FromMinutes(15));
        await ShouldBeProblem(await SignIn(token, a.Tenant.Id, Pin, device), HttpStatusCode.Locked, "pin_locked");
    }

    [Fact]
    public async Task Sign_in_needs_a_tenantId_and_a_device()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var device = new DeviceInfo(Guid.CreateVersion7(), null);
        await ShouldBeProblem(await Post("/api/v1/auth/google", new GoogleSignInRequest(token, null, Pin, device)),
            HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google", new GoogleSignInRequest(token, Guid.Empty, Pin, device)),
            HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google", new GoogleSignInRequest(token, Guid.NewGuid(), Pin, new DeviceInfo(Guid.Empty, null))),
            HttpStatusCode.BadRequest, "validation");
    }

    [Fact]
    public async Task The_email_is_updated_when_the_google_account_changes_it()
    {
        var sub = FakeGoogleVerifier.NewSubject();
        var a = await Register(FakeGoogleVerifier.Token(sub, "old@gmail.com"));
        var b = await SignInOk(FakeGoogleVerifier.Token(sub, "new@gmail.com"), a.Tenant.Id, Pin, Guid.CreateVersion7());

        (await Me(b)).User.GoogleEmail.Should().Be("new@gmail.com");
    }

    // ------------------------------------------------------------ forgot PIN

    [Fact]
    public async Task Forgot_PIN_with_google_sets_a_new_PIN_clears_the_lock_and_ends_every_session()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var a = await Register(token);
        var device = Guid.CreateVersion7();
        for (var i = 0; i < 5; i++) await SignIn(token, a.Tenant.Id, "999999", device); // locked

        var res = await Post("/api/v1/auth/google/pin/reset", new GoogleResetPinRequest(token, a.Tenant.Id, "654321"));
        res.StatusCode.Should().Be(HttpStatusCode.NoContent, await res.Content.ReadAsStringAsync());

        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(a.RefreshToken)), HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await ShouldBeProblem(await SignIn(token, a.Tenant.Id, Pin, device), HttpStatusCode.Unauthorized, "invalid_credentials");
        (await SignInOk(token, a.Tenant.Id, "654321", device)).Tenant.Id.Should().Be(a.Tenant.Id);
    }

    [Fact]
    public async Task Forgot_PIN_validates_the_new_PIN() =>
        await ShouldBeProblem(
            await Post("/api/v1/auth/google/pin/reset", new GoogleResetPinRequest(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject()), Guid.NewGuid(), "12ab56")),
            HttpStatusCode.BadRequest, "validation");

    // ------------------------------------------------------------ shops registered by phone (OTP)

    [Fact]
    public async Task A_phone_and_PIN_never_attach_a_phone_shop_to_a_google_account()
    {
        var phone = NewPhone();
        var legacy = await RegisterByOtp(phone);
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());

        // The old link body (phone + right PIN) and the shop's tenantId with a phone: neither works.
        await ShouldBeProblem(await Post("/api/v1/auth/google",
                new { idToken = token, phone, pin = Pin, device = new DeviceInfo(Guid.CreateVersion7(), null) }),
            HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/google",
                new { idToken = token, tenantId = legacy.Tenant.Id, phone, pin = Pin, device = new DeviceInfo(Guid.CreateVersion7(), null) }),
            HttpStatusCode.NotFound, "shop_not_found");

        (await Shops(token)).Shops.Should().BeEmpty();
        await using var db = _sql.CreateContext(legacy.Tenant.Id);
        (await db.Users.SingleAsync()).GoogleSubject.Should().BeNull();
    }

    // ------------------------------------------------------------ OTP switch

    [Fact]
    public async Task With_OTP_off_the_SMS_endpoints_answer_otp_disabled_and_send_nothing()
    {
        var phone = NewPhone();
        await ShouldBeProblem(await Post("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register)), HttpStatusCode.Forbidden, "otp_disabled");
        await ShouldBeProblem(await Post("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Reset)), HttpStatusCode.Forbidden, "otp_disabled");
        await ShouldBeProblem(await Post("/api/v1/auth/register",
                new RegisterRequest(phone, "123456", "ဆိုင်", "grocery", null, Pin, new DeviceInfo(Guid.CreateVersion7(), null))),
            HttpStatusCode.Forbidden, "otp_disabled");
        await ShouldBeProblem(await Post("/api/v1/auth/pin/reset", new ResetPinRequest(phone, "123456", Pin)), HttpStatusCode.Forbidden, "otp_disabled");
        _api.Sms.Count(phone).Should().Be(0);
    }

    [Fact]
    public async Task OTP_is_off_by_default_when_nothing_is_configured()
    {
        // ApiFactory turns OTP on for the OTP suites; remove the setting to see the real default.
        await using var api = new ApiFactory(_sql.ConnectionString, settings: new Dictionary<string, string?> { ["Auth:OtpEnabled"] = null });
        await ShouldBeProblem(await api.CreateClient().PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(NewPhone(), OtpPurpose.Register), Json),
            HttpStatusCode.Forbidden, "otp_disabled");
    }

    // ------------------------------------------------------------ rate limit

    [Fact]
    public async Task Google_endpoints_are_limited_per_google_account()
    {
        await using var api = new ApiFactory(_sql.ConnectionString, authPerPhone: 2,
            settings: new Dictionary<string, string?> { ["Auth:OtpEnabled"] = "false" });
        var http = api.CreateClient();
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());

        (await http.PostAsJsonAsync("/api/v1/auth/google/shops", new GoogleShopsRequest(token), Json)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await http.PostAsJsonAsync("/api/v1/auth/google", new GoogleSignInRequest(token, Guid.NewGuid(), Pin,
            new DeviceInfo(Guid.CreateVersion7(), null)), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        // Same account, any Google endpoint: one bucket.
        await ShouldBeProblem(await http.PostAsJsonAsync("/api/v1/auth/google/pin/reset", new GoogleResetPinRequest(token, Guid.NewGuid(), Pin), Json),
            HttpStatusCode.TooManyRequests, "rate_limited");
        // Another account from the same IP is unaffected.
        (await http.PostAsJsonAsync("/api/v1/auth/google/shops", new GoogleShopsRequest(FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject())), Json))
            .StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task A_made_up_phone_in_a_google_body_does_not_buy_a_fresh_rate_limit_bucket()
    {
        await using var api = new ApiFactory(_sql.ConnectionString, authPerPhone: 2,
            settings: new Dictionary<string, string?> { ["Auth:OtpEnabled"] = "false" });
        var http = api.CreateClient();
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        object Body() => new { idToken = token, tenantId = Guid.NewGuid(), phone = NewPhone(), pin = Pin,
            device = new DeviceInfo(Guid.CreateVersion7(), null) };

        (await http.PostAsJsonAsync("/api/v1/auth/google", Body(), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await http.PostAsJsonAsync("/api/v1/auth/google", Body(), Json)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        await ShouldBeProblem(await http.PostAsJsonAsync("/api/v1/auth/google", Body(), Json), HttpStatusCode.TooManyRequests, "rate_limited");
    }

    [Fact]
    public async Task Tokens_that_are_not_JWTs_share_one_rate_limit_bucket()
    {
        await using var api = new ApiFactory(_sql.ConnectionString, authPerPhone: 2);
        var http = api.CreateClient();
        foreach (var junk in new[] { "x", "y" })
            (await http.PostAsJsonAsync("/api/v1/auth/google/shops", new GoogleShopsRequest(junk), Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        await ShouldBeProblem(await http.PostAsJsonAsync("/api/v1/auth/google/shops", new GoogleShopsRequest("z"), Json),
            HttpStatusCode.TooManyRequests, "rate_limited");
    }

    // ------------------------------------------------------------ helpers

    private static string NewPhone() => "+9597" + Interlocked.Increment(ref _phoneSeq).ToString().PadLeft(8, '0')[..8];

    private Task<HttpResponseMessage> Post<T>(string url, T body) => _http.PostAsJsonAsync(url, body, Json);

    private static GoogleRegisterRequest RegisterBody(string token, string template = "grocery", string? ownerPhone = null,
        string pin = Pin, Guid? deviceId = null, string shopName = "ရွှေဆိုင်") =>
        new(token, shopName, template, "ဗဟန်း", ownerPhone ?? NewPhone(), pin, new DeviceInfo(deviceId ?? Guid.CreateVersion7(), "Pixel"));

    private async Task<AuthResponse> Register(string token, string template = "grocery", string? ownerPhone = null,
        Guid? deviceId = null, string shopName = "ရွှေဆိုင်")
    {
        var res = await Post("/api/v1/auth/google/register", RegisterBody(token, template, ownerPhone, Pin, deviceId, shopName));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    /// <summary>A shop from before Google: registered with SMS OTP on an API where OTP was on.</summary>
    private async Task<AuthResponse> RegisterByOtp(string phone)
    {
        var otpApi = _sql.Api; // the shared factory has OTP on
        var http = otpApi.CreateClient();
        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var res = await http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(phone, otpApi.Sms.LastCode(phone), "ဖုန်းဆိုင်", "grocery", null, Pin, new DeviceInfo(Guid.CreateVersion7(), "A")), Json);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private async Task<GoogleShopsResponse> Shops(string token)
    {
        var res = await Post("/api/v1/auth/google/shops", new GoogleShopsRequest(token));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<GoogleShopsResponse>(Json))!;
    }

    private Task<HttpResponseMessage> SignIn(string token, Guid tenantId, string pin, Guid deviceId) =>
        Post("/api/v1/auth/google", new GoogleSignInRequest(token, tenantId, pin, new DeviceInfo(deviceId, "Galaxy")));

    private async Task<AuthResponse> SignInOk(string token, Guid tenantId, string pin, Guid deviceId)
    {
        var res = await SignIn(token, tenantId, pin, deviceId);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private async Task<MeResponse> Me(AuthResponse auth)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "/api/v1/me");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        var res = await _http.SendAsync(req);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<MeResponse>(Json))!;
    }

    private static async Task ShouldBeProblem(HttpResponseMessage res, HttpStatusCode status, string code)
    {
        var body = await res.Content.ReadAsStringAsync();
        res.StatusCode.Should().Be(status, body);
        res.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        JsonDocument.Parse(body).RootElement.GetProperty("code").GetString().Should().Be(code);
    }
}
