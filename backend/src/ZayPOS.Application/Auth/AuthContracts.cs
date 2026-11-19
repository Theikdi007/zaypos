using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Common;

namespace ZayPOS.Application.Auth;

public sealed record DeviceInfo(Guid Id, string? Name);

public sealed record OtpRequest(string Phone, OtpPurpose Purpose);

public sealed record OtpResponse(DateTime ExpiresAt);

public sealed record RegisterRequest(
    string Phone, string Otp, string ShopName, string TemplateId, string? Township, string Pin, DeviceInfo Device);

public sealed record LoginRequest(string Phone, string Pin, DeviceInfo Device);

public sealed record RefreshRequest(string RefreshToken);

public sealed record ResetPinRequest(string Phone, string Otp, string NewPin);

/// <summary>POST /auth/google/shops: "who is this user" — the shops of this Google account.</summary>
public sealed record GoogleShopsRequest(string IdToken);

public sealed record GoogleShopsResponse(string? Email, IReadOnlyList<GoogleShop> Shops);

public sealed record GoogleShop(Guid TenantId, string Name, string TemplateId, UserRole Role);

/// <summary>
/// POST /auth/google: sign in on this phone. Either <see cref="TenantId"/> (a shop of this Google account) or
/// <see cref="Phone"/> (a shop registered by phone before Google: links the account to it), plus the shop's PIN.
/// </summary>
public sealed record GoogleSignInRequest(string IdToken, Guid? TenantId, string? Phone, string Pin, DeviceInfo Device);

/// <summary>POST /auth/google/register. <see cref="OwnerPhone"/> is a contact number (Tenants.Phone), NOT verified.</summary>
public sealed record GoogleRegisterRequest(
    string IdToken, string ShopName, string TemplateId, string? Township, string OwnerPhone, string Pin, DeviceInfo Device);

/// <summary>POST /auth/google/pin/reset.</summary>
public sealed record GoogleResetPinRequest(string IdToken, Guid TenantId, string NewPin);

public sealed record AuthResponse(
    string AccessToken,
    DateTime AccessTokenExpiresAt,
    string RefreshToken,
    DateTime RefreshTokenExpiresAt,
    AuthUser User,
    AuthTenant Tenant,
    AuthDevice Device);

public sealed record AuthUser(Guid Id, string Name, UserRole Role);

public sealed record AuthTenant(Guid Id, string Name, string TemplateId, TenantPlan Plan);

public sealed record AuthDevice(Guid Id, string Code, int LastSeq);

/// <summary>An auth failure that maps 1:1 to a ProblemDetails response.</summary>
public sealed class AuthException(int status, string code, string detail, TimeSpan? retryAfter = null)
    : ApiException(status, code, detail, retryAfter)
{

    public static AuthException Validation(string detail) => new(400, "validation", detail);
    public static AuthException OtpInvalid() => new(400, "otp_invalid", "The code is wrong or has expired.");
    public static AuthException InvalidCredentials() => new(401, "invalid_credentials", "Phone or PIN is wrong.");
    public static AuthException InvalidRefreshToken() => new(401, "invalid_refresh_token", "Sign in again.");
    public static AuthException OtpDisabled() =>
        new(403, "otp_disabled", "Phone verification by SMS is turned off. Sign in with Google.");
    public static AuthException GoogleTokenInvalid() =>
        new(401, "google_token_invalid", "The Google sign-in is not valid. Sign in with Google again.");
    public static AuthException GoogleUnavailable() =>
        new(503, "google_unavailable", "Google sign-in can't be checked right now. Try again shortly.", TimeSpan.FromSeconds(30));
    public static AuthException ShopNotFound() =>
        new(404, "shop_not_found", "This Google account has no such shop.");
}
