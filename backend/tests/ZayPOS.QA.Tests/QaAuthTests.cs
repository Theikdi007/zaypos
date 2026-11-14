using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Account;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>QA round 1 — section 1 (AUTH), 3 (FEAT) and 10 (DEV) cases proven against the real API.</summary>
[Collection(QaSqlCollection.Name)]
public class QaAuthTests(SqlServerFixture sql)
{
    private readonly HttpClient _http = sql.Api.CreateClient();

    // TC-AUTH-01 (API half): the dev SMS sender gets "ZayPOS code: ######".
    [Fact]
    public async Task TC_AUTH_01_otp_request_sends_a_six_digit_ZayPOS_code()
    {
        var phone = NewPhone();
        var res = await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json);
        res.StatusCode.Should().Be(HttpStatusCode.Accepted);
        sql.Api.Sms.LastCode(phone).Should().MatchRegex("^[0-9]{6}$");
        sql.Api.Sms.Count(phone).Should().Be(1);
    }

    // TC-AUTH-03: 5 wrong codes kill the code; a NEW code must be requested and then works.
    [Fact]
    public async Task TC_AUTH_03_five_wrong_otps_kill_the_code_and_a_new_code_works()
    {
        var phone = NewPhone();
        await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json);
        var good = sql.Api.Sms.LastCode(phone);
        var wrong = good == "000000" ? "111111" : "000000";
        RegisterRequest Body(string otp) => new(phone, otp, "QA", "grocery", null, Pin, new DeviceInfo(Guid.CreateVersion7(), "x"));

        for (var i = 0; i < 5; i++)
        {
            var r = await _http.PostAsJsonAsync("/api/v1/auth/register", Body(wrong), Json);
            r.StatusCode.Should().Be(HttpStatusCode.BadRequest);
            (await Problem(r)).GetProperty("code").GetString().Should().Be("otp_invalid");
        }
        var dead = await _http.PostAsJsonAsync("/api/v1/auth/register", Body(good), Json);
        (await Problem(dead)).GetProperty("code").GetString().Should().Be("otp_invalid", "the code is dead after 5 wrong tries");

        await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json);
        var fresh = await _http.PostAsJsonAsync("/api/v1/auth/register", Body(sql.Api.Sms.LastCode(phone)), Json);
        fresh.StatusCode.Should().Be(HttpStatusCode.OK, await fresh.Content.ReadAsStringAsync());
    }

    // TC-AUTH-05: a code older than 5 minutes is refused as expired (control: 4:59 still works).
    [Fact]
    public async Task TC_AUTH_05_otp_older_than_five_minutes_is_refused()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var api = new ApiFactory(sql.ConnectionString,
            services: s => { s.RemoveAll<TimeProvider>(); s.AddSingleton<TimeProvider>(clock); });
        var http = api.CreateClient();
        RegisterRequest Body(string phone, string otp) =>
            new(phone, otp, "QA", "grocery", null, Pin, new DeviceInfo(Guid.CreateVersion7(), "x"));

        var expired = NewPhone();
        await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(expired, OtpPurpose.Register), Json);
        var fresh = NewPhone();
        await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(fresh, OtpPurpose.Register), Json);

        clock.Now += TimeSpan.FromMinutes(4) + TimeSpan.FromSeconds(59);
        var ok = await http.PostAsJsonAsync("/api/v1/auth/register", Body(fresh, api.Sms.LastCode(fresh)), Json);
        ok.StatusCode.Should().Be(HttpStatusCode.OK, "4:59 is still inside the 5-minute lifetime");

        clock.Now += TimeSpan.FromSeconds(2); // 5:01
        var late = await http.PostAsJsonAsync("/api/v1/auth/register", Body(expired, api.Sms.LastCode(expired)), Json);
        late.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await Problem(late)).GetProperty("code").GetString().Should().Be("otp_invalid");
    }

    // TC-AUTH-06: register again with a registered phone → refused, still exactly one shop.
    [Fact]
    public async Task TC_AUTH_06_registered_phone_cannot_register_again_and_no_second_shop()
    {
        var shop = await NewShop(sql.Api);

        var otp = await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(shop.Phone, OtpPurpose.Register), Json);
        otp.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await Problem(otp)).GetProperty("code").GetString().Should().Be("phone_registered");

        // Even straight to /register (with any code): refused before the OTP is looked at.
        var reg = await _http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(shop.Phone, "123456", "Second", "pharmacy", null, Pin, new DeviceInfo(Guid.CreateVersion7(), "x")), Json);
        reg.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await Problem(reg)).GetProperty("code").GetString().Should().Be("phone_registered");

        // Raw SQL across all tenants (the tenant filter must stay bypass-free outside AuthRepository).
        await using var db = sql.CreateContext(null);
        var phone = shop.Phone;
        (await db.Database.SqlQuery<int>($"SELECT COUNT(*) AS Value FROM Tenants WHERE Phone = {phone}").SingleAsync())
            .Should().Be(1);
    }

    // TC-AUTH-09: unknown phone and wrong PIN give the SAME response (status, code, title, detail).
    [Fact]
    public async Task TC_AUTH_09_unknown_phone_looks_exactly_like_a_wrong_pin()
    {
        var shop = await NewShop(sql.Api);
        var wrongPin = await _http.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(shop.Phone, "999999", new DeviceInfo(Guid.CreateVersion7(), "x")), Json);
        var unknown = await _http.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(NewPhone(), "999999", new DeviceInfo(Guid.CreateVersion7(), "x")), Json);

        unknown.StatusCode.Should().Be(wrongPin.StatusCode);
        var a = await Problem(wrongPin);
        var b = await Problem(unknown);
        foreach (var field in new[] { "code", "title", "detail", "status" })
            b.TryGetProperty(field, out var bv).Should().Be(a.TryGetProperty(field, out var av));
        b.GetProperty("code").GetString().Should().Be(a.GetProperty("code").GetString());
        b.GetProperty("detail").GetString().Should().Be(a.GetProperty("detail").GetString());
    }

    // TC-FEAT-01: one shop per template; server feature flags = ShopTemplates mapping (which a Domain test ties to shop_template.dart).
    [Theory]
    [InlineData("grocery")]
    [InlineData("pharmacy")]
    [InlineData("phone")]
    [InlineData("fashion")]
    [InlineData("hardware")]
    [InlineData("service")]
    [InlineData("other")]
    public async Task TC_FEAT_01_every_template_registers_with_its_feature_flags(string template)
    {
        var shop = await NewShop(sql.Api, template);
        var me = await shop.Http.GetFromJsonAsync<MeResponse>("/api/v1/me", Json);
        me!.Tenant.TemplateId.Should().Be(template);
        me.Features.Should().BeEquivalentTo(ShopTemplates.FeaturesFor(template));
    }

    // TC-DEV-04: a reinstall (new device id) registers as the NEXT code; old receipts are untouched.
    // Also: a revoked device's code is never handed out again.
    [Fact]
    public async Task TC_DEV_04_reinstall_gets_a_new_code_and_old_receipts_are_unaffected()
    {
        var a = await NewShop(sql.Api);
        var b = await Login(sql.Api, a);
        b.Auth.Device.Code.Should().Be("B");
        var product = await AddProduct(a, 10_000);
        var (saleB, saleBId) = Checkout(b, "B-0001", product, 1000, 600);
        (await PushOne(b, saleB)).Outcome.Should().Be(UnitOutcome.Applied);

        // Owner removes the old B (lost / reinstalled), the reinstalled app logs in with a new install id.
        (await a.Http.DeleteAsync($"/api/v1/devices/{b.DeviceId}")).StatusCode.Should().Be(HttpStatusCode.NoContent);
        var c = await Login(sql.Api, a);
        c.Auth.Device.Code.Should().Be("C", "a revoked code is never reused (receipt numbers would collide)");
        c.Auth.Device.LastSeq.Should().Be(0);

        var (saleC, _) = Checkout(c, "C-0001", product, 1000, 600);
        (await PushOne(c, saleC)).Outcome.Should().Be(UnitOutcome.Applied);

        await using var db = sql.CreateContext(a.TenantId);
        var sales = await db.Sales.OrderBy(s => s.No).Select(s => new { s.Id, s.No, s.DeviceId }).ToListAsync();
        sales.Select(s => s.No).Should().Equal("B-0001", "C-0001");
        sales[0].Id.Should().Be(saleBId);
        sales[0].DeviceId.Should().Be(b.DeviceId);
    }
}
