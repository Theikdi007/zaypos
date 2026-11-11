using ZayPOS.Application.Abstractions;

namespace ZayPOS.Api.Auth;

/// <summary>Tenant from the JWT <c>tid</c> claim. Never from the request body.</summary>
public sealed class HttpCurrentTenant(IHttpContextAccessor accessor) : ICurrentTenant
{
    public const string TenantClaim = "tid";

    public Guid? TenantId =>
        Guid.TryParse(accessor.HttpContext?.User.FindFirst(TenantClaim)?.Value, out var id) ? id : null;
}
