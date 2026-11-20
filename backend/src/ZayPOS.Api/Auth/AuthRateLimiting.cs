using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using ZayPOS.Application.Auth;
using IPNetwork = System.Net.IPNetwork;

namespace ZayPOS.Api.Auth;

/// <summary>
/// /auth/* limits. Every auth request is limited per client IP (high: Myanmar carriers put many
/// phones behind one CGNAT address); otp/pin-reset are also limited per normalized phone
/// from the body, so one number can't be hammered from many IPs. The Google endpoints are limited
/// the same way per Google account: the <c>sub</c> read from the ID token's payload WITHOUT
/// verifying it (like the phone: anyone can spend someone's partition for a minute, nobody can
/// skip it). A Google call is keyed by its token only: any other body field is ignored, so a
/// made-up "phone" can't buy a fresh partition.
/// </summary>
public static class AuthRateLimiting
{
    public const string PhoneItemKey = "zaypos.auth.phone";
    private static readonly string[] PhonePaths = ["/api/v1/auth/otp", "/api/v1/auth/pin/reset"];
    private static readonly string[] GooglePaths =
        ["/api/v1/auth/google", "/api/v1/auth/google/shops", "/api/v1/auth/google/register", "/api/v1/auth/google/pin/reset"];

    public static IServiceCollection AddAuthRateLimiting(this IServiceCollection services, IConfiguration config)
    {
        var perIp = config.GetValue("RateLimiting:AuthPerIpPerMinute", 120);
        var perPhone = config.GetValue("RateLimiting:AuthPerPhonePerMinute", 10);

        services.AddRateLimiter(o =>
        {
            o.GlobalLimiter = PartitionedRateLimiter.CreateChained(
                PartitionedRateLimiter.Create<HttpContext, string>(http =>
                    IsAuth(http.Request.Path)
                        ? Window("ip:" + (http.Connection.RemoteIpAddress?.ToString() ?? "unknown"), perIp)
                        : RateLimitPartition.GetNoLimiter("-")),
                PartitionedRateLimiter.Create<HttpContext, string>(http =>
                    http.Items[PhoneItemKey] is string phone
                        ? Window("phone:" + phone, perPhone)
                        : RateLimitPartition.GetNoLimiter("-")));

            o.OnRejected = async (ctx, ct) =>
            {
                var http = ctx.HttpContext;
                http.Response.StatusCode = StatusCodes.Status429TooManyRequests;
                if (ctx.Lease.TryGetMetadata(MetadataName.RetryAfter, out var wait))
                    http.Response.Headers.RetryAfter = Math.Ceiling(wait.TotalSeconds).ToString(CultureInfo.InvariantCulture);
                var problems = http.RequestServices.GetRequiredService<IProblemDetailsService>();
                await problems.WriteAsync(new ProblemDetailsContext
                {
                    HttpContext = http,
                    ProblemDetails = new ProblemDetails
                    {
                        Status = 429, Title = "rate_limited", Detail = "Too many requests. Try again shortly.",
                        Extensions = { ["code"] = "rate_limited" },
                    },
                });
            };
        });
        return services;
    }

    /// <summary>
    /// Reads "phone" (otp/pin-reset) or the ID token's unverified "sub" (Google) from the JSON body;
    /// the body stays readable for the endpoint.
    /// </summary>
    public static IApplicationBuilder UseAuthPhonePartition(this IApplicationBuilder app) => app.Use(async (http, next) =>
    {
        var phonePath = IsPhonePath(http.Request.Path);
        var googlePath = IsGooglePath(http.Request.Path);
        if (HttpMethods.IsPost(http.Request.Method) && (phonePath || googlePath)
            && http.Request.ContentLength is null or <= 16 * 1024)
        {
            http.Request.EnableBuffering(bufferThreshold: 16 * 1024, bufferLimit: 16 * 1024);
            try
            {
                using var doc = await JsonDocument.ParseAsync(http.Request.Body, cancellationToken: http.RequestAborted);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    string? phone = null, idToken = null;
                    foreach (var p in doc.RootElement.EnumerateObject())
                    {
                        if (p.Value.ValueKind != JsonValueKind.String) continue;
                        if (phone is null && p.Name.Equals("phone", StringComparison.OrdinalIgnoreCase)) phone = p.Value.GetString();
                        else if (idToken is null && p.Name.Equals("idToken", StringComparison.OrdinalIgnoreCase)) idToken = p.Value.GetString();
                    }
                    if (googlePath)
                    {
                        http.Items[PhoneItemKey] = "google:" + (UnverifiedSubject(idToken) ?? "none");
                    }
                    else if (!string.IsNullOrWhiteSpace(phone))
                    {
                        var raw = phone.Trim();
                        // Invalid numbers still get a partition, so junk input can't dodge the limit.
                        http.Items[PhoneItemKey] = PhoneNumbers.Normalize(raw) ?? "raw:" + raw[..Math.Min(raw.Length, 32)];
                    }
                }
            }
            catch (JsonException)
            {
                // Not JSON: the endpoint will answer 400; the IP limit still applies.
            }
            catch (IOException)
            {
                // Body over the buffer limit.
            }
            http.Request.Body.Position = 0;
        }
        await next();
    });

    private static bool IsAuth(PathString path) => path.StartsWithSegments("/api/v1/auth", StringComparison.OrdinalIgnoreCase);

    private static bool IsPhonePath(PathString path) =>
        PhonePaths.Any(p => path.Equals(p, StringComparison.OrdinalIgnoreCase));

    private static bool IsGooglePath(PathString path) =>
        GooglePaths.Any(p => path.Equals(p, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// The "sub" of a JWT's payload, NOT verified: only a rate-limit key. Null when it isn't a JWT
    /// (every such request shares the "none" partition, so garbage can't dodge the limit).
    /// </summary>
    internal static string? UnverifiedSubject(string? jwt)
    {
        if (string.IsNullOrEmpty(jwt) || jwt.Length > 8 * 1024) return null;
        var parts = jwt.Split('.');
        if (parts.Length != 3) return null;
        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            using var doc = JsonDocument.Parse(Convert.FromBase64String(payload));
            return doc.RootElement.ValueKind == JsonValueKind.Object
                   && doc.RootElement.TryGetProperty("sub", out var sub) && sub.ValueKind == JsonValueKind.String
                ? sub.GetString() is { Length: > 0 and <= 255 } s ? s : null
                : null;
        }
        catch (Exception e) when (e is FormatException or JsonException)
        {
            return null;
        }
    }

    private static RateLimitPartition<string> Window(string key, int permits) =>
        RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = permits, Window = TimeSpan.FromMinutes(1), QueueLimit = 0,
        });
}

/// <summary>
/// The client IP (rate limits) and scheme (Https:Require) behind Caddy. Phones connect straight to Caddy
/// (api.zaypos.app is not proxied by Cloudflare: Myanmar networks cut connections to Cloudflare-proxied
/// hosts). Caddy replaces any X-Forwarded-For / X-Forwarded-Proto a client sent with the real peer address
/// and https, and drops CF-Connecting-IP. The API believes X-Forwarded-For / -Proto ONLY when the TCP peer is
/// in ForwardedHeaders:TrustedNetworks(Override): in production Caddy's fixed address alone. Nothing from
/// Cloudflare is trusted any more (a client could send CF-Connecting-IP to dodge the per-IP limit).
/// Disabled in Development.
/// </summary>
public static class ProxyForwarding
{
    public sealed class Settings
    {
        public bool Enabled { get; set; }
        public string[] TrustedNetworks { get; set; } = [];

        /// <summary>When set: comma-separated CIDRs that replace <see cref="TrustedNetworks"/> (config arrays only merge).</summary>
        public string? TrustedNetworksOverride { get; set; }

        public IEnumerable<string> Networks() => string.IsNullOrWhiteSpace(TrustedNetworksOverride)
            ? TrustedNetworks
            : TrustedNetworksOverride.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    public const string Section = "ForwardedHeaders";

    public static Settings Read(IConfiguration config) => config.GetSection(Section).Get<Settings>() ?? new Settings();

    public static bool AddProxyForwarding(this IServiceCollection services, IConfiguration config, IHostEnvironment env)
    {
        var settings = Read(config);
        // No trusted proxy configured = no forwarding at all. NOT an empty list: with no known proxies or
        // networks ASP.NET's middleware believes X-Forwarded-For from ANY client (seen in AuthTests), and a
        // phone could pick its own rate-limit bucket. Production refuses to start without one (Deployment.cs).
        if (!settings.Enabled || env.IsDevelopment() || !settings.Networks().Any()) return false;

        services.Configure<ForwardedHeadersOptions>(o =>
        {
            o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            // The standard X-Forwarded-For (from Caddy), not Cloudflare's CF-Connecting-IP.
            o.ForwardedForHeaderName = ForwardedHeadersDefaults.XForwardedForHeaderName;
            // Only the last hop, the one Caddy wrote: Caddy replaces the header, so there is only one.
            o.ForwardLimit = 1;
            o.KnownProxies.Clear();
            o.KnownIPNetworks.Clear();
            foreach (var cidr in settings.Networks())
                o.KnownIPNetworks.Add(IPNetwork.Parse(cidr));
        });
        return true;
    }
}
