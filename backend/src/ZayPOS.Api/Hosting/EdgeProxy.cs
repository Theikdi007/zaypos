using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace ZayPOS.Api.Hosting;

/// <summary>
/// The App Engine edge proxy (docs/deploy/fallback-routes.md). Myanmar networks refuse our server's IP, but they let
/// through Google's own front end, so the app can also reach the API through a small proxy on App Engine. Caddy then
/// sees Google's address as the client. The proxy proves itself with a shared secret (<see cref="SecretHeader"/>) and
/// passes the phone's address in <see cref="ClientIpHeader"/>. Only when the secret matches does the API take that
/// address as the client (rate limits per phone, not one bucket for every shop behind Google).
///
/// Both headers are removed from EVERY request, matching or not, so nothing later in the pipeline (or in logs) sees
/// them. A wrong or missing secret is just an ordinary request from the TCP peer: no error, nothing revealed.
/// The secret is never logged.
/// </summary>
public static class EdgeProxy
{
    public const string Section = "EdgeProxy";
    public const string SecretHeader = "X-ZayPOS-Edge";
    public const string ClientIpHeader = "X-ZayPOS-Client-IP";
    /// <summary>HttpContext.Items flag: this request came through the edge proxy.</summary>
    public const string ViaItemKey = "zaypos.via.edge";
    /// <summary>Shorter secrets are refused at startup (the proxy uses 32 random bytes, base64 = 44 chars).</summary>
    public const int MinSecretLength = 32;

    public sealed class Settings
    {
        /// <summary>
        /// Comma-separated accepted secrets (env EdgeProxy__Secrets ← EDGE_PROXY_SECRETS in .env). Two during a
        /// rotation: current,next. Empty = no edge proxy: the headers are still stripped, never believed.
        /// </summary>
        public string? Secrets { get; set; }

        public IReadOnlyList<string> List() =>
            (Secrets ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    public static Settings Read(IConfiguration config) => config.GetSection(Section).Get<Settings>() ?? new Settings();

    /// <summary>Startup check: a configured secret must be long enough. Null when fine.</summary>
    public static string? ConfigError(IConfiguration config) =>
        Read(config).List().Any(s => s.Length < MinSecretLength)
            ? $"EdgeProxy:Secrets: every secret must be at least {MinSecretLength} characters (openssl rand -base64 32)."
            : null;

    /// <summary>Must run after UseForwardedHeaders (which sets the peer from Caddy) and before rate limiting.</summary>
    public static IApplicationBuilder UseEdgeProxyClientIp(this IApplicationBuilder app)
    {
        var config = app.ApplicationServices.GetRequiredService<IConfiguration>();
        var error = ConfigError(config);
        if (error is not null) throw new InvalidOperationException(error);
        // Only hashes are kept: equal-length inputs to FixedTimeEquals, so neither content nor length leaks by timing.
        var hashes = Read(config).List().Select(s => SHA256.HashData(Encoding.UTF8.GetBytes(s))).ToArray();
        var log = app.ApplicationServices.GetRequiredService<ILoggerFactory>().CreateLogger("ZayPOS.EdgeProxy");

        return app.Use((http, next) =>
        {
            var headers = http.Request.Headers;
            if (!headers.ContainsKey(SecretHeader) && !headers.ContainsKey(ClientIpHeader)) return next(http);

            string? secret = headers[SecretHeader].Count == 1 ? headers[SecretHeader].ToString() : null;
            string? clientIp = headers[ClientIpHeader].Count == 1 ? headers[ClientIpHeader].ToString() : null;
            headers.Remove(SecretHeader);
            headers.Remove(ClientIpHeader);

            if (secret is null) return next(http); // a client sent only a client-IP header: ignored

            if (!Matches(secret, hashes))
            {
                log.LogWarning("edge_secret_mismatch from {Peer}", http.Connection.RemoteIpAddress);
                return next(http);
            }
            if (clientIp is null || !IPAddress.TryParse(clientIp.Trim(), out var ip))
            {
                log.LogWarning("edge_client_ip_invalid");
                return next(http);
            }

            http.Connection.RemoteIpAddress = ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip;
            http.Items[ViaItemKey] = true;
            return next(http);
        });
    }

    private static bool Matches(string secret, byte[][] hashes)
    {
        if (hashes.Length == 0) return false;
        var given = SHA256.HashData(Encoding.UTF8.GetBytes(secret));
        var match = false;
        foreach (var h in hashes) match |= CryptographicOperations.FixedTimeEquals(given, h); // no early exit
        return match;
    }
}
