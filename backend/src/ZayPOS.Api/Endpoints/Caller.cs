using System.Security.Claims;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Sync;
using ZayPOS.Infrastructure.Auth;

namespace ZayPOS.Api.Endpoints;

public static class Caller
{
    public const string OwnerPolicy = "owner";

    /// <summary>Tenant, user and device come from the token only.</summary>
    public static SyncCaller From(ClaimsPrincipal user)
    {
        Guid Claim(string type) =>
            Guid.TryParse(user.FindFirstValue(type), out var id) && id != Guid.Empty
                ? id
                : throw new ApiException(401, "invalid_token", $"Token has no valid '{type}' claim.");
        return new SyncCaller(Claim(ZayPosClaims.Tenant), Claim(ZayPosClaims.User), Claim(ZayPosClaims.Device));
    }

    /// <summary>
    /// A revoked phone's access token stays valid for up to 15 minutes; refuse it on every
    /// account endpoint, not just sync.
    /// </summary>
    public static TBuilder RequireActiveDevice<TBuilder>(this TBuilder builder) where TBuilder : IEndpointConventionBuilder =>
        builder.AddEndpointFilter(async (ctx, next) =>
        {
            var http = ctx.HttpContext;
            var db = http.RequestServices.GetRequiredService<IAppDb>();
            await SyncAccess.RequireActiveDeviceAsync(db, From(http.User), http.RequestAborted);
            return await next(ctx);
        });
}
