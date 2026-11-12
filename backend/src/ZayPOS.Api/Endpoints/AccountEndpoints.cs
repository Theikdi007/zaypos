using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Account;
using ZayPOS.Application.Catalog;
using ZayPOS.Application.Subscription;

namespace ZayPOS.Api.Endpoints;

/// <summary>README §5: me, presets, devices, subscription.</summary>
public static class AccountEndpoints
{
    public static readonly TimeSpan PresetCacheFor = TimeSpan.FromMinutes(10);

    public static IEndpointRouteBuilder MapAccountEndpoints(this IEndpointRouteBuilder app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization().RequireActiveDevice();

        v1.MapGet("/me", async (ClaimsPrincipal user, AccountService svc, CancellationToken ct) =>
                Results.Ok(await svc.MeAsync(Caller.From(user), ct)))
            .WithTags("Me").Produces<MeResponse>();

        // ---------------------------------------------------------------- presets
        v1.MapGet("/catalog/presets", GetPresets).WithTags("Catalog")
            .Produces<PresetCatalog>().Produces(StatusCodes.Status304NotModified);

        // ---------------------------------------------------------------- devices
        var devices = v1.MapGroup("/devices").WithTags("Devices");
        devices.MapGet("", async (ClaimsPrincipal user, AccountService svc, CancellationToken ct) =>
                Results.Ok(await svc.DevicesAsync(Caller.From(user), ct)))
            .Produces<IReadOnlyList<DeviceInfoDto>>();
        devices.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AccountService svc, CancellationToken ct) =>
            {
                await svc.RevokeDeviceAsync(Caller.From(user), id, ct);
                return Results.NoContent();
            })
            .RequireAuthorization(Caller.OwnerPolicy)
            .Produces(StatusCodes.Status204NoContent);

        // ---------------------------------------------------------------- subscription
        var sub = v1.MapGroup("/subscription").WithTags("Subscription");
        sub.MapGet("", async (SubscriptionService svc, CancellationToken ct) => Results.Ok(await svc.GetAsync(ct)))
            .Produces<SubscriptionResponse>();
        sub.MapPost("/screenshot-url", (ScreenshotUrlRequest req, ClaimsPrincipal user, SubscriptionService svc) =>
                Results.Ok(svc.ScreenshotUrl(Caller.From(user), req)))
            .RequireAuthorization(Caller.OwnerPolicy)
            .Produces<PresignedUpload>();
        sub.MapPost("/payments", async (CreateSubscriptionPayment req, ClaimsPrincipal user, SubscriptionService svc, CancellationToken ct) =>
            {
                var (payment, created) = await svc.CreatePaymentAsync(Caller.From(user), req, ct);
                return created ? Results.Created($"/api/v1/subscription/payments/{payment.Id}", payment) : Results.Ok(payment);
            })
            .RequireAuthorization(Caller.OwnerPolicy)
            .Produces<SubscriptionPaymentDto>(StatusCodes.Status201Created)
            .Produces<SubscriptionPaymentDto>();

        return app;
    }

    /// <summary>
    /// Presets are global and change only with a deploy: serialized once per template, cached in
    /// memory, served with a strong ETag so the app can revalidate for free (304).
    /// </summary>
    private static async Task<IResult> GetPresets(
        string? template, HttpContext http, PresetCatalogService svc, IMemoryCache cache, IOptions<JsonOptions> json, CancellationToken ct)
    {
        template = string.IsNullOrWhiteSpace(template) ? await svc.TenantTemplateAsync(ct) : template.Trim();
        var (body, etag) = (await cache.GetOrCreateAsync("presets:" + template, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = PresetCacheFor;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(await svc.GetAsync(template, ct), json.Value.SerializerOptions);
            return (bytes, $"\"{Convert.ToHexStringLower(SHA256.HashData(bytes))[..32]}\"");
        }))!;

        http.Response.Headers.ETag = etag;
        http.Response.Headers.CacheControl = "private, max-age=3600";
        var ifNoneMatch = http.Request.Headers.IfNoneMatch.ToString();
        if (ifNoneMatch.Split(',').Select(t => t.Trim()).Any(t => t == etag || t == "*"))
            return Results.StatusCode(StatusCodes.Status304NotModified);
        return Results.Bytes(body, "application/json; charset=utf-8");
    }
}
