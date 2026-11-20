using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using ZayPOS.Application.Auth;

namespace ZayPOS.Infrastructure.Auth;

/// <summary>
/// "Auth:Google" config section. <see cref="ClientIds"/>: every OAuth client id whose ID tokens we accept
/// (web/server, Android debug + release, iOS). Env: <c>Auth__Google__ClientIds</c>, comma-separated.
/// </summary>
public sealed class GoogleAuthOptions
{
    public const string Section = "Auth:Google";
    public const string DefaultMetadataAddress = "https://accounts.google.com/.well-known/openid-configuration";

    /// <summary>Comma-separated (env-friendly) or a config array; both are read.</summary>
    public string ClientIds { get; set; } = "";
    public string[] ClientIdList { get; set; } = [];

    /// <summary>Google's OpenID configuration (points at the JWKS). Only tests change it.</summary>
    public string MetadataAddress { get; set; } = DefaultMetadataAddress;

    public IReadOnlyList<string> Audiences() =>
        ClientIds.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Concat(ClientIdList.Select(c => c.Trim()).Where(c => c.Length > 0))
            .Distinct(StringComparer.Ordinal)
            .ToList();

    public bool IsConfigured => Audiences().Count > 0;
}

/// <summary>Google's current signing keys. <paramref name="refresh"/> = a token named a key we don't have.</summary>
public interface IGoogleSigningKeys
{
    Task<IReadOnlyCollection<SecurityKey>> GetAsync(bool refresh, CancellationToken ct);
}

/// <summary>Google's OpenID configuration → JWKS, cached (24 h, at most one forced refresh per 5 min).</summary>
public sealed class GoogleOpenIdSigningKeys : IGoogleSigningKeys
{
    private readonly ConfigurationManager<OpenIdConnectConfiguration> _config;

    public GoogleOpenIdSigningKeys(IOptions<GoogleAuthOptions> options, HttpClient http)
    {
        _config = new ConfigurationManager<OpenIdConnectConfiguration>(
            options.Value.MetadataAddress,
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever(http) { RequireHttps = true })
        {
            AutomaticRefreshInterval = TimeSpan.FromHours(24),
            RefreshInterval = TimeSpan.FromMinutes(5),
        };
    }

    public async Task<IReadOnlyCollection<SecurityKey>> GetAsync(bool refresh, CancellationToken ct)
    {
        if (refresh) _config.RequestRefresh();
        var config = await _config.GetConfigurationAsync(ct);
        return config.SigningKeys.ToList();
    }
}

/// <summary>
/// Verifies a Google ID token: RS256 signature by one of Google's keys, issuer, audience = one of our
/// client ids, expiry (and iat not in the future), 60 s clock skew, and a subject. Nothing else from the
/// token is trusted; the email is kept for support only.
/// </summary>
public sealed class GoogleIdTokenVerifier(
    IOptions<GoogleAuthOptions> options,
    IGoogleSigningKeys keys,
    TimeProvider clock,
    ILogger<GoogleIdTokenVerifier> log) : IGoogleIdTokenVerifier
{
    public static readonly string[] Issuers = ["accounts.google.com", "https://accounts.google.com"];
    public static readonly TimeSpan ClockSkew = TimeSpan.FromSeconds(60);

    /// <summary>Google ID tokens are ~1 KB; anything far bigger is not one.</summary>
    public const int MaxTokenLength = 8 * 1024;

    private readonly JsonWebTokenHandler _handler = new() { MapInboundClaims = false };

    public async Task<GoogleIdentity> VerifyAsync(string? idToken, CancellationToken ct)
    {
        var audiences = options.Value.Audiences();
        if (audiences.Count == 0)
        {
            log.LogError("Google sign-in refused: Auth:Google:ClientIds is not configured");
            throw AuthException.GoogleUnavailable();
        }
        if (string.IsNullOrWhiteSpace(idToken) || idToken.Length > MaxTokenLength)
            throw AuthException.GoogleTokenInvalid();

        var token = idToken.Trim();
        string? kid;
        try
        {
            kid = new JsonWebToken(token).Kid;
        }
        catch (Exception e) when (e is ArgumentException or SecurityTokenMalformedException)
        {
            throw AuthException.GoogleTokenInvalid();
        }

        var signingKeys = await KeysAsync(refresh: false, ct);
        if (kid is not null && signingKeys.All(k => k.KeyId != kid))
            signingKeys = await KeysAsync(refresh: true, ct); // Google rotated its keys (refresh is rate-limited)

        var result = await ValidateAsync(token, audiences, signingKeys);

        if (!result.IsValid)
        {
            log.LogInformation("Google ID token refused: {Reason}", result.Exception?.GetType().Name ?? "invalid");
            throw AuthException.GoogleTokenInvalid();
        }

        var claims = result.ClaimsIdentity;
        var subject = claims.FindFirst("sub")?.Value;
        if (string.IsNullOrWhiteSpace(subject) || subject.Length > 255) throw AuthException.GoogleTokenInvalid();

        // A token "issued" in the future is forged or from a broken clock: refuse either way.
        if (result.SecurityToken is JsonWebToken jwt && jwt.IssuedAt != DateTime.MinValue
            && jwt.IssuedAt > clock.GetUtcNow().UtcDateTime + ClockSkew)
            throw AuthException.GoogleTokenInvalid();

        return new GoogleIdentity(subject, claims.FindFirst("email")?.Value);
    }

    private async Task<IReadOnlyCollection<SecurityKey>> KeysAsync(bool refresh, CancellationToken ct)
    {
        try
        {
            return await keys.GetAsync(refresh, ct);
        }
        catch (Exception e) when (e is InvalidOperationException or HttpRequestException or IOException or TaskCanceledException
                                  && !ct.IsCancellationRequested)
        {
            log.LogWarning("Google signing keys could not be loaded: {Error}", e.Message);
            throw AuthException.GoogleUnavailable();
        }
    }

    private async Task<TokenValidationResult> ValidateAsync(
        string token, IReadOnlyList<string> audiences, IReadOnlyCollection<SecurityKey> signingKeys)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        return await _handler.ValidateTokenAsync(token, new TokenValidationParameters
        {
            ValidIssuers = Issuers,
            ValidAudiences = audiences,
            IssuerSigningKeys = signingKeys,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            RequireSignedTokens = true,
            RequireExpirationTime = true,
            ValidateIssuerSigningKey = true,
            TryAllIssuerSigningKeys = false, // the kid must match: an unknown kid triggers one key refresh
            ClockSkew = ClockSkew,
            LifetimeValidator = (notBefore, expires, _, _) =>
                expires is { } exp && exp + ClockSkew > now && (notBefore is not { } nbf || nbf - ClockSkew <= now),
            NameClaimType = "sub",
        });
    }
}
