using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Infrastructure.Auth;
using Microsoft.IdentityModel.JsonWebTokens;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Api.Tests;

[Collection(SqlServerCollection.Name)]
public class AuthTests(SqlServerFixture sql)
{
    private const string Pin = "123456";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private static int _phoneSeq = Random.Shared.Next(1_000_000, 9_000_000);

    private readonly HttpClient _http = sql.Api.CreateClient();

    // ------------------------------------------------------------ register

    [Fact]
    public async Task Register_creates_tenant_owner_template_features_and_device_A()
    {
        var phone = NewPhone();
        var deviceId = Guid.CreateVersion7();

        var auth = await Register(phone, template: "pharmacy", deviceId: deviceId, deviceName: "Samsung A15");

        auth.Device.Should().Be(new AuthDevice(deviceId, "A", 0));
        auth.User.Role.Should().Be(UserRole.Owner);
        auth.Tenant.TemplateId.Should().Be("pharmacy");
        auth.Tenant.Plan.Should().Be(TenantPlan.Free);
        auth.RefreshTokenExpiresAt.Should().BeCloseTo(DateTime.UtcNow.AddDays(90), TimeSpan.FromMinutes(1));

        var jwt = new JsonWebToken(auth.AccessToken);
        jwt.GetClaim("sub").Value.Should().Be(auth.User.Id.ToString());
        jwt.GetClaim("tid").Value.Should().Be(auth.Tenant.Id.ToString());
        jwt.GetClaim("did").Value.Should().Be(deviceId.ToString());
        jwt.GetClaim("role").Value.Should().Be("owner");
        (jwt.ValidTo - jwt.IssuedAt).Should().Be(TimeSpan.FromMinutes(15));

        await using var db = sql.CreateContext(auth.Tenant.Id);
        var features = await db.TenantFeatures.ToDictionaryAsync(f => f.FeatureKey, f => f.Enabled);
        features.Should().BeEquivalentTo(ShopTemplates.FeaturesFor("pharmacy"));
        features.Where(f => f.Value).Select(f => f.Key).Should()
            .BeEquivalentTo("quickSale", "stock", "presetCatalog", "expiryBatch");

        var user = await db.Users.SingleAsync();
        user.Phone.Should().Be(phone);
        user.PinHash.Should().NotContain(Pin);
        (await db.Devices.SingleAsync()).Name.Should().Be("Samsung A15");
    }

    [Fact]
    public async Task Phone_in_local_09_format_is_normalized_to_E164()
    {
        var d = NextDigits(8);
        var local = $"09 7{d[..2]} {d[2..5]} {d[5..]}";
        var e164 = PhoneNumbers.Normalize(local)!;

        var auth = await Register(local);

        await using var db = sql.CreateContext(auth.Tenant.Id);
        (await db.Users.SingleAsync()).Phone.Should().Be(e164);
    }

    [Fact]
    public async Task Registered_phone_cannot_register_again()
    {
        var phone = NewPhone();
        await Register(phone);

        var res = await Post("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register));
        await ShouldBeProblem(res, HttpStatusCode.Conflict, "phone_registered");
    }

    [Fact]
    public async Task Register_validates_input()
    {
        var phone = NewPhone();
        await ShouldBeProblem(await Post("/api/v1/auth/otp", new OtpRequest("12345", OtpPurpose.Register)),
            HttpStatusCode.BadRequest, "validation");

        await RequestOtp(phone, OtpPurpose.Register);
        var otp = sql.Api.Sms.LastCode(phone);
        await ShouldBeProblem(await Post("/api/v1/auth/register", RegisterBody(phone, otp, template: "bakery")),
            HttpStatusCode.BadRequest, "validation");
        await ShouldBeProblem(await Post("/api/v1/auth/register", RegisterBody(phone, otp, pin: "1234")),
            HttpStatusCode.BadRequest, "validation");
    }

    // ------------------------------------------------------------ OTP

    [Fact]
    public async Task Wrong_otp_costs_an_attempt_and_five_wrong_kill_the_code()
    {
        var phone = NewPhone();
        await RequestOtp(phone, OtpPurpose.Register);
        var good = sql.Api.Sms.LastCode(phone);
        var wrong = good == "000000" ? "111111" : "000000";

        for (var i = 0; i < AuthRules.OtpMaxAttempts; i++)
            await ShouldBeProblem(await Post("/api/v1/auth/register", RegisterBody(phone, wrong)),
                HttpStatusCode.BadRequest, "otp_invalid");

        await ShouldBeProblem(await Post("/api/v1/auth/register", RegisterBody(phone, good)),
            HttpStatusCode.BadRequest, "otp_invalid");
    }

    [Fact]
    public async Task Otp_is_limited_to_three_per_phone_per_hour()
    {
        var phone = NewPhone();
        for (var i = 0; i < AuthRules.OtpPerPhonePerHour; i++)
            await RequestOtp(phone, OtpPurpose.Register);

        var res = await Post("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register));
        await ShouldBeProblem(res, HttpStatusCode.TooManyRequests, "otp_rate_limited");
        res.Headers.RetryAfter.Should().NotBeNull();
        sql.Api.Sms.Count(phone).Should().Be(3);
    }

    [Fact]
    public async Task Reset_otp_for_unknown_phone_looks_sent_but_sends_nothing()
    {
        var phone = NewPhone();
        var res = await Post("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Reset));
        res.StatusCode.Should().Be(HttpStatusCode.Accepted);
        sql.Api.Sms.Count(phone).Should().Be(0);
    }

    // ------------------------------------------------------------ sign in on another phone + devices
    // (Google + the shop + the PIN; there is no phone + PIN sign-in.)

    [Fact]
    public async Task Sign_in_on_a_new_phone_gets_the_next_code_and_the_same_phone_keeps_it()
    {
        var (owner, token) = await GoogleShop();
        owner.Device.Code.Should().Be("A");

        var second = Guid.CreateVersion7();
        (await SignInOk(token, owner, second)).Device.Code.Should().Be("B");
        (await SignInOk(token, owner, second)).Device.Code.Should().Be("B");
        (await SignInOk(token, owner, Guid.CreateVersion7())).Device.Code.Should().Be("C");
        (await SignInOk(token, owner, owner.Device.Id)).Device.Code.Should().Be("A");

        await using var db = sql.CreateContext(owner.Tenant.Id);
        (await db.Devices.OrderBy(d => d.Code).Select(d => d.Code).ToListAsync()).Should().Equal("A", "B", "C");
    }

    [Fact]
    public async Task Device_id_of_another_shop_is_a_conflict()
    {
        var (shop1, _) = await GoogleShop();
        var (shop2, token2) = await GoogleShop();

        await ShouldBeProblem(await SignIn(token2, shop2, Pin, shop1.Device.Id), HttpStatusCode.Conflict, "device_conflict");
    }

    [Fact]
    public async Task Five_wrong_pins_lock_the_account_for_15_minutes()
    {
        var (auth, token) = await GoogleShop();
        var device = Guid.CreateVersion7();

        for (var i = 1; i < AuthRules.PinMaxFailures; i++)
            await ShouldBeProblem(await SignIn(token, auth, "999999", device), HttpStatusCode.Unauthorized, "invalid_credentials");

        var fifth = await SignIn(token, auth, "999999", device);
        await ShouldBeProblem(fifth, HttpStatusCode.Locked, "pin_locked");
        fifth.Headers.RetryAfter!.Delta.Should().Be(TimeSpan.FromMinutes(15));

        // Even the right PIN is refused while locked.
        await ShouldBeProblem(await SignIn(token, auth, Pin, device), HttpStatusCode.Locked, "pin_locked");

        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.LockedUntil.Should().BeCloseTo(DateTime.UtcNow.AddMinutes(15), TimeSpan.FromMinutes(1));
            user.LockedUntil = DateTime.UtcNow.AddSeconds(-1); // let the lock run out
            await db.SaveChangesAsync();
        }

        (await SignIn(token, auth, Pin, device)).StatusCode.Should().Be(HttpStatusCode.OK);
        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.FailedPinCount.Should().Be(0);
            user.LockedUntil.Should().BeNull();
        }
    }

    // ------------------------------------------------------------ refresh

    [Fact]
    public async Task Refresh_rotates_the_token_and_the_new_one_keeps_working()
    {
        var first = await Register(NewPhone());

        var second = await RefreshOk(first.RefreshToken);
        second.RefreshToken.Should().NotBe(first.RefreshToken);
        second.Device.Id.Should().Be(first.Device.Id);
        new JsonWebToken(second.AccessToken).GetClaim("tid").Value.Should().Be(first.Tenant.Id.ToString());
        var third = await RefreshOk(second.RefreshToken);

        var tokens = await DeviceTokens(first);
        tokens.Should().HaveCount(3);
        tokens[0].ReplacedById.Should().Be(tokens[1].Id);
        tokens[1].ReplacedById.Should().Be(tokens[2].Id);
        tokens.Count(t => t.RevokedAt == null).Should().Be(1);
        (await RefreshOk(third.RefreshToken)).Should().NotBeNull();
    }

    [Fact]
    public async Task Retry_within_2_minutes_of_rotation_rotates_the_unseen_replacement_instead()
    {
        var first = await Register(NewPhone());
        await RefreshOk(first.RefreshToken);              // response "lost" on a flaky network

        var retried = await RefreshOk(first.RefreshToken); // phone retries with the old token

        var tokens = await DeviceTokens(first);
        tokens.Should().HaveCount(3);
        tokens[0].ReplacedById.Should().Be(tokens[1].Id);
        tokens[1].RevokedAt.Should().NotBeNull("the replacement the phone never received is revoked");
        tokens[1].ReplacedById.Should().Be(tokens[2].Id);
        tokens[2].RevokedAt.Should().BeNull("the device chain is NOT revoked");
        (await RefreshOk(retried.RefreshToken)).Should().NotBeNull();
    }

    [Fact]
    public async Task Reuse_more_than_2_minutes_after_rotation_revokes_the_device_chain()
    {
        var first = await Register(NewPhone());
        var second = await RefreshOk(first.RefreshToken);
        await using (var db = sql.CreateContext(first.Tenant.Id))
        {
            var old = await db.RefreshTokens.SingleAsync(t => t.DeviceId == first.Device.Id && t.ReplacedById != null);
            old.RevokedAt = DateTime.UtcNow.AddMinutes(-3);
            await db.SaveChangesAsync();
        }

        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(second.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        (await DeviceTokens(first)).Should().OnlyContain(t => t.RevokedAt != null);
    }

    [Fact]
    public async Task Reuse_of_a_token_revoked_without_replacement_revokes_the_device_chain()
    {
        var (first, token) = await GoogleShop();
        var again = await SignInOk(token, first, first.Device.Id); // signing in again revokes first's token (no replacement)

        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(again.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        (await DeviceTokens(first)).Should().OnlyContain(t => t.RevokedAt != null);
    }

    [Fact]
    public async Task Reuse_after_the_replacement_was_already_used_revokes_the_device_chain()
    {
        var first = await Register(NewPhone());
        var second = await RefreshOk(first.RefreshToken);
        await RefreshOk(second.RefreshToken); // the phone clearly got `second`

        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        (await DeviceTokens(first)).Should().OnlyContain(t => t.RevokedAt != null);
    }

    [Fact]
    public async Task Two_concurrent_refreshes_with_the_same_token_both_succeed_and_leave_one_session()
    {
        var first = await Register(NewPhone());
        var other = sql.Api.CreateClient();

        var results = await Task.WhenAll(
            _http.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken), Json),
            other.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken), Json));

        foreach (var r in results)
            r.StatusCode.Should().Be(HttpStatusCode.OK, await r.Content.ReadAsStringAsync());
        var tokens = await DeviceTokens(first);
        tokens.Should().HaveCount(3);
        tokens.Count(t => t.RevokedAt == null).Should().Be(1);
    }

    [Fact]
    public async Task Garbage_refresh_token_is_rejected()
    {
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest("not-a-token")),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
    }

    // ------------------------------------------------------------ PIN reset

    [Fact]
    public async Task Pin_reset_changes_the_pin_unlocks_and_ends_all_sessions()
    {
        var phone = NewPhone();
        var auth = await Register(phone);
        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.FailedPinCount = 3;
            user.LockedUntil = DateTime.UtcNow.AddMinutes(10); // locked
            await db.SaveChangesAsync();
        }

        await RequestOtp(phone, OtpPurpose.Reset);
        var res = await Post("/api/v1/auth/pin/reset", new ResetPinRequest(phone, sql.Api.Sms.LastCode(phone), "654321"));
        res.StatusCode.Should().Be(HttpStatusCode.NoContent);

        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(auth.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.LockedUntil.Should().BeNull();
            user.FailedPinCount.Should().Be(0);
            new PinHasher().Verify(user, user.PinHash, "654321").Should().NotBe(PinCheck.Failed);
            new PinHasher().Verify(user, user.PinHash, Pin).Should().Be(PinCheck.Failed);
        }
    }

    [Fact]
    public async Task Pin_reset_needs_a_reset_code_not_a_register_code()
    {
        var phone = NewPhone();
        await RequestOtp(phone, OtpPurpose.Register);
        var registerCode = sql.Api.Sms.LastCode(phone);
        await Register(phone, otp: registerCode);

        await ShouldBeProblem(await Post("/api/v1/auth/pin/reset", new ResetPinRequest(phone, registerCode, "654321")),
            HttpStatusCode.BadRequest, "otp_invalid");
    }

    // ------------------------------------------------------------ rate limiting

    [Fact]
    public async Task Auth_endpoints_are_rate_limited_per_client_ip()
    {
        await using var api = new ApiFactory(sql.ConnectionString, authPerIp: 2);
        var http = api.CreateClient();
        var body = new RefreshRequest("garbage");

        (await http.PostAsJsonAsync("/api/v1/auth/refresh", body, Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.PostAsJsonAsync("/api/v1/auth/refresh", body, Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var third = await http.PostAsJsonAsync("/api/v1/auth/refresh", body, Json);
        await ShouldBeProblem(third, HttpStatusCode.TooManyRequests, "rate_limited");
        third.Headers.RetryAfter.Should().NotBeNull();
    }

    [Fact]
    public async Task Otp_and_pin_reset_are_also_limited_per_normalized_phone()
    {
        await using var api = new ApiFactory(sql.ConnectionString, authPerPhone: 2);
        var http = api.CreateClient();
        var d = NextDigits(8);
        var e164 = $"+9597{d}";
        var local = $"09 7{d[..2]} {d[2..5]} {d[5..]}";
        ResetPinRequest Reset(string phone) => new(phone, "000000", Pin);

        (await http.PostAsJsonAsync("/api/v1/auth/pin/reset", Reset(e164), Json)).StatusCode.Should().NotBe(HttpStatusCode.TooManyRequests);
        (await http.PostAsJsonAsync("/api/v1/auth/pin/reset", Reset(local), Json)).StatusCode.Should().NotBe(HttpStatusCode.TooManyRequests);
        // Same number in either format, either endpoint: one bucket.
        await ShouldBeProblem(await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(local, OtpPurpose.Reset), Json),
            HttpStatusCode.TooManyRequests, "rate_limited");
        await ShouldBeProblem(await http.PostAsJsonAsync("/api/v1/auth/pin/reset", Reset(e164), Json),
            HttpStatusCode.TooManyRequests, "rate_limited");
        // Another phone from the same IP is unaffected.
        (await http.PostAsJsonAsync("/api/v1/auth/pin/reset", Reset(NewPhone()), Json)).StatusCode.Should().NotBe(HttpStatusCode.TooManyRequests);
    }

    [Fact]
    public async Task A_client_never_chooses_its_rate_limit_key_with_forwarded_headers_not_even_from_a_cloudflare_address()
    {
        // Phones connect straight to Caddy now (api.zaypos.app is not proxied): no address outside the configured
        // proxy (Caddy) is trusted, Cloudflare's included. Spoofed headers must not buy new per-IP buckets.
        var body = new RefreshRequest("garbage");
        HttpRequestMessage Req(string header, string clientIp)
        {
            var m = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/refresh") { Content = JsonContent.Create(body, options: Json) };
            m.Headers.Add(header, clientIp);
            return m;
        }

        foreach (var peer in new[] { "173.245.48.10" /* a Cloudflare edge */, "198.51.100.7" /* a phone */ })
        foreach (var header in new[] { "CF-Connecting-IP", "X-Forwarded-For" })
        {
            await using var api = new ApiFactory(sql.ConnectionString, authPerIp: 1, remoteIp: IPAddress.Parse(peer));
            var http = api.CreateClient();
            (await http.SendAsync(Req(header, "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
            (await http.SendAsync(Req(header, "203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.TooManyRequests,
                $"{header} from {peer} must be ignored: the bucket is the TCP peer's");
        }
    }

    // ------------------------------------------------------------ helpers

    private static string NewPhone() => "+9597" + NextDigits(8);

    private static string NextDigits(int n) =>
        Interlocked.Increment(ref _phoneSeq).ToString().PadLeft(n, '0')[..n];

    private Task<HttpResponseMessage> Post<T>(string url, T body) => _http.PostAsJsonAsync(url, body, Json);

    private async Task RequestOtp(string phone, OtpPurpose purpose)
    {
        var res = await Post("/api/v1/auth/otp", new OtpRequest(phone, purpose));
        res.StatusCode.Should().Be(HttpStatusCode.Accepted, await res.Content.ReadAsStringAsync());
    }

    private static RegisterRequest RegisterBody(string phone, string otp, string template = "grocery",
        string pin = Pin, Guid? deviceId = null, string? deviceName = null) =>
        new(phone, otp, "ရွှေဆိုင်", template, "ဗဟန်း", pin, new DeviceInfo(deviceId ?? Guid.CreateVersion7(), deviceName));

    private async Task<AuthResponse> Register(string phone, string template = "grocery", Guid? deviceId = null,
        string? deviceName = null, string? otp = null)
    {
        if (otp is null)
        {
            await RequestOtp(phone, OtpPurpose.Register);
            otp = sql.Api.Sms.LastCode(PhoneNumbers.Normalize(phone)!);
        }
        var res = await Post("/api/v1/auth/register", RegisterBody(phone, otp, template, Pin, deviceId, deviceName));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    /// <summary>A shop registered with (fake) Google; the token is how its other phones sign in.</summary>
    private async Task<(AuthResponse Auth, string Token)> GoogleShop()
    {
        var token = FakeGoogleVerifier.Token(FakeGoogleVerifier.NewSubject());
        var res = await Post("/api/v1/auth/google/register",
            new GoogleRegisterRequest(token, "ရွှေဆိုင်", "grocery", null, NewPhone(), Pin, new DeviceInfo(Guid.CreateVersion7(), "A15")));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return ((await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!, token);
    }

    private Task<HttpResponseMessage> SignIn(string token, AuthResponse shop, string pin, Guid deviceId) =>
        Post("/api/v1/auth/google", new GoogleSignInRequest(token, shop.Tenant.Id, pin, new DeviceInfo(deviceId, "Redmi 13")));

    private async Task<AuthResponse> SignInOk(string token, AuthResponse shop, Guid deviceId)
    {
        var res = await SignIn(token, shop, Pin, deviceId);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private async Task<AuthResponse> RefreshOk(string refreshToken)
    {
        var res = await Post("/api/v1/auth/refresh", new RefreshRequest(refreshToken));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private async Task<List<ZayPOS.Domain.Tenancy.RefreshToken>> DeviceTokens(AuthResponse auth)
    {
        await using var db = sql.CreateContext(auth.Tenant.Id);
        return await db.RefreshTokens.AsNoTracking().Where(t => t.DeviceId == auth.Device.Id)
            .OrderBy(t => t.CreatedAt).ThenBy(t => t.Id).ToListAsync();
    }

    private static async Task ShouldBeProblem(HttpResponseMessage res, HttpStatusCode status, string code)
    {
        var body = await res.Content.ReadAsStringAsync();
        res.StatusCode.Should().Be(status, body);
        res.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        JsonDocument.Parse(body).RootElement.GetProperty("code").GetString().Should().Be(code);
    }
}
