using System.Security.Claims;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Sync;

namespace ZayPOS.Api.Endpoints;

public static class SyncEndpoints
{
    public static IEndpointRouteBuilder MapSyncEndpoints(this IEndpointRouteBuilder app)
    {
        var sync = app.MapGroup("/api/v1/sync").WithTags("Sync").RequireAuthorization();

        sync.MapPost("/push", async (PushRequest req, ClaimsPrincipal user, SyncPushService svc, CancellationToken ct) =>
                Results.Ok(await svc.PushAsync(Caller.From(user), req, ct)))
            .Produces<PushResponse>();

        sync.MapGet("/pull", async (string? cursor, int? limit, ClaimsPrincipal user, IAppDb db, ISyncPull pull, CancellationToken ct) =>
            {
                var caller = Caller.From(user);
                await SyncAccess.RequireActiveDeviceAsync(db, caller, ct);
                return Results.Ok(await pull.PullAsync(SyncCursor.Parse(cursor), limit ?? SyncLimits.PullDefaultLimit, ct));
            })
            .Produces<PullResponse>();

        sync.MapPost("/issues/{id:guid}/resolve", async (Guid id, ClaimsPrincipal user, IAppDb db, SyncIssueService svc, CancellationToken ct) =>
            {
                await SyncAccess.RequireActiveDeviceAsync(db, Caller.From(user), ct);
                return Results.Ok(await svc.ResolveAsync(id, ct));
            })
            .RequireAuthorization(Caller.OwnerPolicy)
            .Produces<SyncIssueRow>();

        // Static and not secret: the app may read it before signing in.
        sync.MapGet("/limits", (HttpContext http) =>
            {
                http.Response.Headers.CacheControl = "public, max-age=3600";
                return Results.Ok(SyncLimits.Describe());
            })
            .AllowAnonymous()
            .Produces<SyncLimitsResponse>();

        return app;
    }
}
