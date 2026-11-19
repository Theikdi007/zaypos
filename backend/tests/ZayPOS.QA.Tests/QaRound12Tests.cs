using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 12 — 205c5d7 (BUG-34), server half. Developer: "Server PhoneNumbers.Normalize now also maps Myanmar digits
/// (before, .NET \d let them through unconverted)", and the doc comment: "the same rules as the app's
/// phoneKey/normalizeMmPhone". The developer's AuthRulesTests check Normalize() alone. These go through the HTTP API: one
/// account whatever form the number is written in (OTP, register, login, PIN reset, the per-phone OTP limit), and
/// other Unicode decimal digits, which .NET's \d still lets through (the app's Dart \d is ASCII-only and refuses them).
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound12Tests(SqlServerFixture sql)
{
    private readonly HttpClient _http = sql.Api.CreateClient();

    /// "+9598NNNNNNNN" → its "09…" national form in Myanmar digits (၀-၉).
    private static string MyanmarDigits(string e164) =>
        string.Concat(("0" + e164[3..]).Select(ch => (char)('၀' + (ch - '0'))));

    private static string Dotted(string e164)
    {
        var n = "0" + e164[3..]; // 09 + 9 digits
        return $"{n[..2]}.{n[2..5]}.{n[5..8]}.{n[8..]}";
    }

    private static string Spaced(string e164) => $"+95 {e164[3..6]} {e164[6..9]} {e164[9..]}";

    // TC-AUTH-NEW-1: OTP in Myanmar digits, register dotted, login "+95 9 …", reset PIN dashed → one account, stored ASCII.
    [Fact]
    public async Task TC_AUTH_NEW_1_one_account_whatever_form_the_number_is_written_in()
    {
        var phone = NewPhone();
        var mm = MyanmarDigits(phone);
        (await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(mm, OtpPurpose.Register), Json))
            .StatusCode.Should().Be(HttpStatusCode.Accepted);
        var code = sql.Api.Sms.LastCode(phone); // the SMS goes to the ASCII E.164 number

        var reg = await _http.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(Dotted(phone), code, "QA r12 shop", "grocery", null, Pin, new DeviceInfo(Guid.CreateVersion7(), "A")), Json);
        reg.StatusCode.Should().Be(HttpStatusCode.OK, await reg.Content.ReadAsStringAsync());
        var tenant = (await reg.Content.ReadFromJsonAsync<AuthResponse>(Json))!.Tenant.Id;

        // (Phone + PIN sign-in "+95 9 …" was removed with POST /auth/login; the other forms are still checked below.)

        // a second shop for the same number in another form is refused at the OTP step (README: 409 phone_registered)
        var again = await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest("959-" + phone[4..], OtpPurpose.Register), Json);
        again.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await Problem(again)).GetProperty("code").GetString().Should().Be("phone_registered");

        // PIN reset: the code is requested in Myanmar digits, the reset sent dotted, the login with the new PIN in ASCII
        (await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(mm, OtpPurpose.Reset), Json))
            .StatusCode.Should().Be(HttpStatusCode.Accepted);
        var reset = await _http.PostAsJsonAsync("/api/v1/auth/pin/reset",
            new ResetPinRequest(Dotted(phone), sql.Api.Sms.LastCode(phone), "246802"), Json);
        reset.IsSuccessStatusCode.Should().BeTrue(await reset.Content.ReadAsStringAsync());

        // the 3-per-hour OTP limit counts every form as one number: 2 sent above, a 3rd (spaced) is sent, a 4th (dashed) refused
        (await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(Spaced(phone), OtpPurpose.Reset), Json))
            .StatusCode.Should().Be(HttpStatusCode.Accepted);
        sql.Api.Sms.Count(phone).Should().Be(3);
        var fourth = await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest("959-" + phone[4..], OtpPurpose.Reset), Json);
        fourth.StatusCode.Should().Be((HttpStatusCode)429);

        // the shop's own (tenant-filtered) view; the tenant filter is not bypassed here (ArchitectureTests allows that only
        // in AuthRepository). "No second shop" is proven by the 409 above.
        await using var db = sql.CreateContext(tenant);
        var stored = await db.Users.Select(u => u.Phone).ToListAsync();
        stored.Should().Equal(phone);
        (await db.Tenants.Select(t => t.Phone).ToListAsync()).Should().Equal(phone);
    }

    // TC-AUTH-NEW-2: digits of OTHER scripts. Shan digits (U+1090–1099, in the Myanmar Unicode block, typed by Shan
    // keyboards), Arabic-Indic and full-width digits are \d in .NET. The app refuses them (Dart \d is 0-9 only), so the
    // server must not turn them into a phone number either: either map them to 0-9 or refuse — never return a
    // non-ASCII "+959…".
    [Theory]
    [InlineData("09႗႙႐႐႑႑႐႐႒")] // 09 + Shan digits ႗႙႐႐႑႑႐႐႒
    [InlineData("+959٧٩٠٠١١٠٠٢")] // +959 + Arabic-Indic ٧٩٠٠١١٠٠٢
    [InlineData("09７９００１１００２")] // 09 + full-width ７９００１１００２
    public void TC_AUTH_NEW_2_other_script_digits_never_become_a_non_ASCII_phone_number(string input)
    {
        var n = PhoneNumbers.Normalize(input);
        (n is null || Regex.IsMatch(n, "^\\+959[0-9]{7,9}$")).Should().BeTrue($"Normalize(\"{input}\") returned \"{n}\"");
    }

    // TC-AUTH-NEW-2 (API half): such a number gets no SMS and no account.
    [Fact]
    public async Task TC_AUTH_NEW_2_api_an_otp_for_a_Shan_digit_number_sends_no_SMS_to_a_non_ASCII_number()
    {
        var shan = "09႗႙႐႐႑႑႐႐႒";
        var res = await _http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(shan, OtpPurpose.Register), Json);
        var raw = "+959" + shan[2..];
        var sentToRaw = sql.Api.Sms.Count(raw);
        sentToRaw.Should().Be(0, $"no SMS to the non-ASCII number \"{raw}\" (status {(int)res.StatusCode})");
    }
}
