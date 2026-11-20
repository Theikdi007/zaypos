using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using ZayPOS.Application.Auth;
using ZayPOS.Infrastructure.Auth;

namespace ZayPOS.Api.Tests;

/// <summary>The real Google ID token checks, against a local RSA key standing in for Google's JWKS.</summary>
public class GoogleIdTokenVerifierTests
{
    private const string Android = "123-android.apps.googleusercontent.com";
    private const string Web = "123-web.apps.googleusercontent.com";
    private const string Ios = "123-ios.apps.googleusercontent.com";

    private static readonly DateTimeOffset T0 = new(2026, 11, 19, 8, 0, 0, TimeSpan.Zero);

    private readonly RsaSecurityKey _google = NewKey("google-1");
    private readonly FixedClock _clock = new(T0);
    private readonly FakeKeys _keys;

    public GoogleIdTokenVerifierTests() => _keys = new FakeKeys(_google);

    private GoogleIdTokenVerifier Verifier(string clientIds = $"{Web}, {Android},{Ios}") =>
        new(Options.Create(new GoogleAuthOptions { ClientIds = clientIds }), _keys, _clock,
            NullLogger<GoogleIdTokenVerifier>.Instance);

    [Theory]
    [InlineData(Web)]
    [InlineData(Android)]
    [InlineData(Ios)]
    public async Task A_valid_token_for_any_of_our_client_ids_gives_the_subject_and_email(string aud)
    {
        var id = await Verifier().VerifyAsync(Sign(aud: aud), default);

        id.Should().Be(new GoogleIdentity("109876543210987654321", "owner@gmail.com"));
    }

    [Theory]
    [InlineData("accounts.google.com")]
    [InlineData("https://accounts.google.com")]
    public async Task Both_google_issuer_spellings_are_accepted(string iss) =>
        (await Verifier().VerifyAsync(Sign(iss: iss), default)).Subject.Should().Be("109876543210987654321");

    [Fact]
    public async Task Email_is_optional() =>
        (await Verifier().VerifyAsync(Sign(email: null), default)).Email.Should().BeNull();

    [Fact]
    public async Task Another_apps_client_id_is_refused() =>
        await Refused(Sign(aud: "999-someone-else.apps.googleusercontent.com"));

    [Theory]
    [InlineData("https://evil.example.com")]
    [InlineData("accounts.google.com.evil.example")]
    public async Task A_foreign_issuer_is_refused(string iss) => await Refused(Sign(iss: iss));

    [Fact]
    public async Task An_expired_token_is_refused_after_the_60_second_skew()
    {
        var token = Sign(expires: T0.AddMinutes(-1).UtcDateTime, issued: T0.AddHours(-1).UtcDateTime);
        await Refused(token);

        var justExpired = Sign(expires: T0.AddSeconds(-30).UtcDateTime, issued: T0.AddHours(-1).UtcDateTime);
        (await Verifier().VerifyAsync(justExpired, default)).Subject.Should().NotBeEmpty("30 s is inside the skew");
    }

    [Fact]
    public async Task A_token_issued_in_the_future_is_refused() =>
        await Refused(Sign(issued: T0.AddMinutes(5).UtcDateTime, expires: T0.AddHours(1).UtcDateTime));

    [Fact]
    public async Task A_token_signed_by_another_key_is_refused()
    {
        var attacker = NewKey("google-1"); // same kid, different key
        await Refused(Sign(key: attacker));
    }

    [Fact]
    public async Task An_unknown_kid_refreshes_the_keys_once_and_then_verifies()
    {
        var rotated = NewKey("google-2");
        _keys.AfterRefresh = rotated;

        (await Verifier().VerifyAsync(Sign(key: rotated), default)).Subject.Should().NotBeEmpty();
        _keys.Refreshes.Should().Be(1);
    }

    [Fact]
    public async Task An_unknown_kid_that_stays_unknown_is_refused_after_one_refresh()
    {
        await Refused(Sign(key: NewKey("not-google")));
        _keys.Refreshes.Should().Be(1);
    }

    [Fact]
    public async Task Alg_none_is_refused()
    {
        var header = B64("""{"alg":"none","typ":"JWT"}""");
        var payload = B64($$"""{"iss":"https://accounts.google.com","aud":"{{Web}}","sub":"1","exp":{{T0.AddHours(1).ToUnixTimeSeconds()}},"iat":{{T0.ToUnixTimeSeconds()}}}""");
        await Refused($"{header}.{payload}.");
    }

    [Fact]
    public async Task HS256_signed_with_the_public_key_is_refused()
    {
        var pub = Encoding.UTF8.GetBytes(_google.Rsa.ExportSubjectPublicKeyInfoPem());
        var hmac = new SymmetricSecurityKey(pub) { KeyId = "google-1" };
        await Refused(Sign(credentials: new SigningCredentials(hmac, SecurityAlgorithms.HmacSha256)));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not-a-jwt")]
    [InlineData("a.b.c")]
    public async Task Garbage_is_refused(string? token) => await Refused(token);

    [Fact]
    public async Task An_oversized_token_is_refused_without_parsing() =>
        await Refused(new string('a', GoogleIdTokenVerifier.MaxTokenLength + 1));

    [Fact]
    public async Task A_token_without_subject_is_refused() => await Refused(Sign(sub: null));

    [Fact]
    public async Task No_configured_client_ids_means_unavailable_not_open()
    {
        var act = () => Verifier(clientIds: " , ").VerifyAsync(Sign(), default);
        (await act.Should().ThrowAsync<AuthException>()).Which.Code.Should().Be("google_unavailable");
    }

    [Fact]
    public async Task Google_keys_unreachable_is_503_google_unavailable()
    {
        _keys.Fail = true;
        var act = () => Verifier().VerifyAsync(Sign(), default);
        var e = (await act.Should().ThrowAsync<AuthException>()).Which;
        e.Code.Should().Be("google_unavailable");
        e.Status.Should().Be(503);
    }

    [Fact]
    public void Client_ids_come_from_the_comma_list_and_the_array()
    {
        var o = new GoogleAuthOptions { ClientIds = $" {Web} ,{Android},", ClientIdList = [Ios, Web] };
        o.Audiences().Should().Equal(Web, Android, Ios);
    }

    // ------------------------------------------------------------ helpers

    private async Task Refused(string? token)
    {
        var act = () => Verifier().VerifyAsync(token, default);
        var e = (await act.Should().ThrowAsync<AuthException>()).Which;
        e.Code.Should().Be("google_token_invalid");
        e.Status.Should().Be(401);
    }

    private string Sign(string aud = Web, string iss = "https://accounts.google.com", string? sub = "109876543210987654321",
        string? email = "owner@gmail.com", DateTime? issued = null, DateTime? expires = null, RsaSecurityKey? key = null,
        SigningCredentials? credentials = null)
    {
        var claims = new List<Claim>();
        if (sub is not null) claims.Add(new Claim("sub", sub));
        if (email is not null) claims.Add(new Claim("email", email));
        var iat = issued ?? T0.AddMinutes(-1).UtcDateTime;
        return new JsonWebTokenHandler { SetDefaultTimesOnTokenCreation = false }.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = iss,
            Audience = aud,
            IssuedAt = iat,
            Expires = expires ?? iat.AddHours(1),
            Subject = new ClaimsIdentity(claims),
            SigningCredentials = credentials ?? new SigningCredentials(key ?? _google, SecurityAlgorithms.RsaSha256),
        });
    }

    private static RsaSecurityKey NewKey(string kid) => new(RSA.Create(2048)) { KeyId = kid };

    private static string B64(string s) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(s)).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private sealed class FakeKeys(RsaSecurityKey initial) : IGoogleSigningKeys
    {
        public RsaSecurityKey? AfterRefresh { get; set; }
        public bool Fail { get; set; }
        public int Refreshes { get; private set; }

        public Task<IReadOnlyCollection<SecurityKey>> GetAsync(bool refresh, CancellationToken ct)
        {
            if (Fail) throw new InvalidOperationException("IDX20803: Unable to obtain configuration");
            if (refresh) Refreshes++;
            // Public halves only, like a JWKS.
            var keys = new List<SecurityKey> { Public(initial) };
            if (refresh && AfterRefresh is not null) keys.Add(Public(AfterRefresh));
            return Task.FromResult<IReadOnlyCollection<SecurityKey>>(keys);
        }

        private static RsaSecurityKey Public(RsaSecurityKey k) => new(k.Rsa.ExportParameters(false)) { KeyId = k.KeyId };
    }

    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
