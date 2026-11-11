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
    : Exception(detail)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public TimeSpan? RetryAfter { get; } = retryAfter;

    public static AuthException Validation(string detail) => new(400, "validation", detail);
    public static AuthException OtpInvalid() => new(400, "otp_invalid", "The code is wrong or has expired.");
    public static AuthException InvalidCredentials() => new(401, "invalid_credentials", "Phone or PIN is wrong.");
    public static AuthException InvalidRefreshToken() => new(401, "invalid_refresh_token", "Sign in again.");
}
