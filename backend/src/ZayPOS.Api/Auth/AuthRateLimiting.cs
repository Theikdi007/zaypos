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
/// phones behind one CGNAT address); otp/login/pin-reset are also limited per normalized phone
/// from the body, so one number can't be hammered from many IPs.
/// </summary>
public static class AuthRateLimiting
{
    public const string PhoneItemKey = "zaypos.auth.phone";
    private static readonly string[] PhonePaths = ["/api/v1/auth/otp", "/api/v1/auth/login", "/api/v1/auth/pin/reset"];

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

    /// <summary>Reads "phone" from the JSON body of otp/login/pin-reset (body stays readable for the endpoint).</summary>
    public static IApplicationBuilder UseAuthPhonePartition(this IApplicationBuilder app) => app.Use(async (http, next) =>
    {
        if (HttpMethods.IsPost(http.Request.Method) && IsPhonePath(http.Request.Path)
            && http.Request.ContentLength is null or <= 16 * 1024)
        {
            http.Request.EnableBuffering(bufferThreshold: 16 * 1024, bufferLimit: 16 * 1024);
            try
            {
                using var doc = await JsonDocument.ParseAsync(http.Request.Body, cancellationToken: http.RequestAborted);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    foreach (var p in doc.RootElement.EnumerateObject())
                    {
                        if (!p.Name.Equals("phone", StringComparison.OrdinalIgnoreCase) || p.Value.ValueKind != JsonValueKind.String)
                            continue;
                        var raw = p.Value.GetString() ?? "";
                        // Invalid numbers still get a partition, so junk input can't dodge the limit.
                        http.Items[PhoneItemKey] = PhoneNumbers.Normalize(raw) ?? "raw:" + raw.Trim()[..Math.Min(raw.Trim().Length, 32)];
                        break;
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

    private static RateLimitPartition<string> Window(string key, int permits) =>
        RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = permits, Window = TimeSpan.FromMinutes(1), QueueLimit = 0,
        });
}

/// <summary>
/// The API sits behind Cloudflare. Trust CF-Connecting-IP only when the TCP peer is a Cloudflare
/// address (list in config: https://www.cloudflare.com/ips/). Disabled in Development.
/// </summary>
public static class CloudflareForwarding
{
    public sealed class Settings
    {
        public bool Enabled { get; set; }
        public string[] TrustedNetworks { get; set; } = [];
    }

    public static bool AddCloudflareForwarding(this IServiceCollection services, IConfiguration config, IHostEnvironment env)
    {
        var settings = config.GetSection("ForwardedHeaders").Get<Settings>() ?? new Settings();
        if (!settings.Enabled || env.IsDevelopment()) return false;

        services.Configure<ForwardedHeadersOptions>(o =>
        {
            o.ForwardedHeaders = ForwardedHeaders.XForwardedFor;
            o.ForwardedForHeaderName = "CF-Connecting-IP";
            o.ForwardLimit = 1;
            o.KnownProxies.Clear();
            o.KnownIPNetworks.Clear();
            foreach (var cidr in settings.TrustedNetworks)
                o.KnownIPNetworks.Add(IPNetwork.Parse(cidr));
        });
        return true;
    }
}
