using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
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
        (await Login(e164, Pin, Guid.CreateVersion7())).StatusCode.Should().Be(HttpStatusCode.OK);
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

    // ------------------------------------------------------------ login + devices

    [Fact]
    public async Task Login_on_a_new_phone_gets_the_next_code_and_the_same_phone_keeps_it()
    {
        var phone = NewPhone();
        var owner = await Register(phone);
        owner.Device.Code.Should().Be("A");

        var second = Guid.CreateVersion7();
        (await LoginOk(phone, second)).Device.Code.Should().Be("B");
        (await LoginOk(phone, second)).Device.Code.Should().Be("B");
        (await LoginOk(phone, Guid.CreateVersion7())).Device.Code.Should().Be("C");
        (await LoginOk(phone, owner.Device.Id)).Device.Code.Should().Be("A");

        await using var db = sql.CreateContext(owner.Tenant.Id);
        (await db.Devices.OrderBy(d => d.Code).Select(d => d.Code).ToListAsync()).Should().Equal("A", "B", "C");
    }

    [Fact]
    public async Task Device_id_of_another_shop_is_a_conflict()
    {
        var shop1 = await Register(NewPhone());
        var phone2 = NewPhone();
        await Register(phone2);

        await ShouldBeProblem(await Login(phone2, Pin, shop1.Device.Id), HttpStatusCode.Conflict, "device_conflict");
    }

    [Fact]
    public async Task Unknown_phone_and_wrong_pin_look_the_same()
    {
        await ShouldBeProblem(await Login(NewPhone(), Pin, Guid.CreateVersion7()),
            HttpStatusCode.Unauthorized, "invalid_credentials");
    }

    [Fact]
    public async Task Five_wrong_pins_lock_the_account_for_15_minutes()
    {
        var phone = NewPhone();
        var auth = await Register(phone);
        var device = Guid.CreateVersion7();

        for (var i = 1; i < AuthRules.PinMaxFailures; i++)
            await ShouldBeProblem(await Login(phone, "999999", device), HttpStatusCode.Unauthorized, "invalid_credentials");

        var fifth = await Login(phone, "999999", device);
        await ShouldBeProblem(fifth, HttpStatusCode.Locked, "pin_locked");
        fifth.Headers.RetryAfter!.Delta.Should().Be(TimeSpan.FromMinutes(15));

        // Even the right PIN is refused while locked.
        await ShouldBeProblem(await Login(phone, Pin, device), HttpStatusCode.Locked, "pin_locked");

        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.LockedUntil.Should().BeCloseTo(DateTime.UtcNow.AddMinutes(15), TimeSpan.FromMinutes(1));
            user.LockedUntil = DateTime.UtcNow.AddSeconds(-1); // let the lock run out
            await db.SaveChangesAsync();
        }

        (await Login(phone, Pin, device)).StatusCode.Should().Be(HttpStatusCode.OK);
        await using (var db = sql.CreateContext(auth.Tenant.Id))
        {
            var user = await db.Users.SingleAsync();
            user.FailedPinCount.Should().Be(0);
            user.LockedUntil.Should().BeNull();
        }
    }

    // ------------------------------------------------------------ refresh

    [Fact]
    public async Task Refresh_rotates_the_token_and_revokes_the_old_one()
    {
        var first = await Register(NewPhone());

        var second = await RefreshOk(first.RefreshToken);
        second.RefreshToken.Should().NotBe(first.RefreshToken);
        second.Device.Id.Should().Be(first.Device.Id);
        new JsonWebToken(second.AccessToken).GetClaim("tid").Value.Should().Be(first.Tenant.Id.ToString());

        // The old token is dead...
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(first.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        // ...and replaying it counts as theft: the whole device session chain is revoked.
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(second.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");

        await using var db = sql.CreateContext(first.Tenant.Id);
        var tokens = await db.RefreshTokens.Where(t => t.DeviceId == first.Device.Id).OrderBy(t => t.CreatedAt).ToListAsync();
        tokens.Should().HaveCount(2).And.OnlyContain(t => t.RevokedAt != null);
        tokens[0].ReplacedById.Should().Be(tokens[1].Id);
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
        for (var i = 0; i < AuthRules.PinMaxFailures; i++)
            await Login(phone, "999999", auth.Device.Id); // now locked

        await RequestOtp(phone, OtpPurpose.Reset);
        var res = await Post("/api/v1/auth/pin/reset", new ResetPinRequest(phone, sql.Api.Sms.LastCode(phone), "654321"));
        res.StatusCode.Should().Be(HttpStatusCode.NoContent);

        await ShouldBeProblem(await Login(phone, Pin, auth.Device.Id), HttpStatusCode.Unauthorized, "invalid_credentials");
        await ShouldBeProblem(await Post("/api/v1/auth/refresh", new RefreshRequest(auth.RefreshToken)),
            HttpStatusCode.Unauthorized, "invalid_refresh_token");
        (await Login(phone, "654321", auth.Device.Id)).StatusCode.Should().Be(HttpStatusCode.OK);
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
    public async Task Auth_endpoints_are_rate_limited_per_client()
    {
        await using var api = new ApiFactory(sql.ConnectionString, authPerMinute: 2);
        var http = api.CreateClient();
        var body = new LoginRequest(NewPhone(), Pin, new DeviceInfo(Guid.CreateVersion7(), null));

        (await http.PostAsJsonAsync("/api/v1/auth/login", body, Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.PostAsJsonAsync("/api/v1/auth/login", body, Json)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.PostAsJsonAsync("/api/v1/auth/login", body, Json)).StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
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

    private Task<HttpResponseMessage> Login(string phone, string pin, Guid deviceId) =>
        Post("/api/v1/auth/login", new LoginRequest(phone, pin, new DeviceInfo(deviceId, "Redmi 13")));

    private async Task<AuthResponse> LoginOk(string phone, Guid deviceId)
    {
        var res = await Login(phone, Pin, deviceId);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private async Task<AuthResponse> RefreshOk(string refreshToken)
    {
        var res = await Post("/api/v1/auth/refresh", new RefreshRequest(refreshToken));
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        return (await res.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
    }

    private static async Task ShouldBeProblem(HttpResponseMessage res, HttpStatusCode status, string code)
    {
        var body = await res.Content.ReadAsStringAsync();
        res.StatusCode.Should().Be(status, body);
        res.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        JsonDocument.Parse(body).RootElement.GetProperty("code").GetString().Should().Be(code);
    }
}
