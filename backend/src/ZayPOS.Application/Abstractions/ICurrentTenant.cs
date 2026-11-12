namespace ZayPOS.Application.Abstractions;

/// <summary>
/// The tenant of the current request, taken from the JWT <c>tid</c> claim —
/// never from the request body. Null when unauthenticated (auth endpoints);
/// tenant-filtered queries then return no rows.
/// </summary>
public interface ICurrentTenant
{
    Guid? TenantId { get; }
}
