using System.Security.Claims;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Sync;
using ZayPOS.Infrastructure.Auth;

namespace ZayPOS.Api.Endpoints;

public static class SyncEndpoints
{
    public static IEndpointRouteBuilder MapSyncEndpoints(this IEndpointRouteBuilder app)
    {
        var sync = app.MapGroup("/api/v1/sync").WithTags("Sync").RequireAuthorization();

        sync.MapPost("/push", async (PushRequest req, ClaimsPrincipal user, SyncPushService svc, CancellationToken ct) =>
                Results.Ok(await svc.PushAsync(Caller(user), req, ct)))
            .Produces<PushResponse>();

        sync.MapGet("/pull", async (string? cursor, int? limit, ClaimsPrincipal user, IAppDb db, ISyncPull pull, CancellationToken ct) =>
            {
                var caller = Caller(user);
                await SyncAccess.RequireActiveDeviceAsync(db, caller, ct);
                return Results.Ok(await pull.PullAsync(SyncCursor.Parse(cursor), limit ?? 500, ct));
            })
            .Produces<PullResponse>();

        return app;
    }

    /// <summary>Tenant, user and device come from the token only.</summary>
    private static SyncCaller Caller(ClaimsPrincipal user)
    {
        Guid Claim(string type) =>
            Guid.TryParse(user.FindFirstValue(type), out var id) && id != Guid.Empty
                ? id
                : throw new ApiException(401, "invalid_token", $"Token has no valid '{type}' claim.");
        return new SyncCaller(Claim(ZayPosClaims.Tenant), Claim(ZayPosClaims.User), Claim(ZayPosClaims.Device));
    }
}
