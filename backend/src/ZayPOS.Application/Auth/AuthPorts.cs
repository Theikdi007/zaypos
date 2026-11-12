using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Auth;

/// <summary>
/// The ONLY data access that runs before a tenant is known (lookups by phone,
/// device, refresh token). Its implementation is the only place allowed to
/// bypass the tenant query filter.
/// </summary>
public interface IAuthRepository
{
    Task<User?> FindUserByPhoneAsync(string phone, CancellationToken ct);
    Task<User?> FindUserAsync(Guid userId, CancellationToken ct);
    Task<Tenant?> FindTenantAsync(Guid tenantId, CancellationToken ct);
    Task<Device?> FindDeviceAsync(Guid deviceId, CancellationToken ct);
    /// <summary>All codes ever issued in the tenant, including revoked devices.</summary>
    Task<IReadOnlyList<string>> DeviceCodesAsync(Guid tenantId, CancellationToken ct);

    Task<int> CountOtpsSinceAsync(string phone, DateTime since, CancellationToken ct);
    /// <summary>Newest challenge that is unconsumed, unexpired and has attempts left.</summary>
    Task<OtpChallenge?> FindOpenOtpAsync(string phone, OtpPurpose purpose, DateTime now, int maxAttempts, CancellationToken ct);

    /// <summary>Untracked: always the current DB state (rotation races re-read it).</summary>
    Task<RefreshToken?> FindRefreshTokenAsync(byte[] tokenHash, CancellationToken ct);
    Task<RefreshToken?> FindRefreshTokenByIdAsync(Guid tokenId, CancellationToken ct);
    /// <summary>Atomically revokes one token if it is still active. False = someone else already did.</summary>
    Task<bool> TryRevokeRefreshTokenAsync(Guid tokenId, Guid? replacedById, DateTime now, CancellationToken ct);
    /// <summary>Revokes every active token of the user (optionally only on one device).</summary>
    Task RevokeRefreshTokensAsync(Guid userId, Guid? deviceId, DateTime now, CancellationToken ct);

    void Add<T>(T entity) where T : class;
    void Discard<T>(T entity) where T : class;
    /// <exception cref="UniqueViolationException">A unique index rejected the write.</exception>
    Task SaveChangesAsync(CancellationToken ct);
    Task<IAuthTransaction> BeginTransactionAsync(CancellationToken ct);
}

public interface IAuthTransaction : IAsyncDisposable
{
    Task CommitAsync(CancellationToken ct);
}

/// <summary>A unique index (e.g. UX_Users_Phone, UX_Devices_Code) rejected a write.</summary>
public sealed class UniqueViolationException(string message, Exception inner) : Exception(message, inner)
{
    public bool Involves(string indexName) => Message.Contains(indexName, StringComparison.OrdinalIgnoreCase);
}

public interface IPinHasher
{
    string Hash(User user, string pin);
    PinCheck Verify(User user, string hash, string pin);
    /// <summary>Burns the same time as <see cref="Verify"/> against a fixed dummy hash (unknown phone).</summary>
    void VerifyDummy(string pin);
}

public enum PinCheck { Failed, Success, SuccessRehashNeeded }

public interface IAccessTokenIssuer
{
    (string Token, DateTime ExpiresAt) Issue(User user, Device device, DateTime now);
}
