using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Auth;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Infrastructure.Auth;

/// <summary>
/// "Jwt" config section. <see cref="SigningKey"/> is a secret: user-secrets in dev,
/// environment/secret store in prod. Never in appsettings*.json.
/// </summary>
public sealed class JwtOptions
{
    public const string Section = "Jwt";
    public const int MinKeyBytes = 32;

    public string Issuer { get; set; } = "zaypos";
    public string Audience { get; set; } = "zaypos-app";
    public string SigningKey { get; set; } = "";
    public int AccessTokenMinutes { get; set; } = 15;

    public SymmetricSecurityKey Key() => new(Encoding.UTF8.GetBytes(SigningKey));
}

/// <summary>Claims: sub (user), tid (tenant), did (device), role.</summary>
public static class ZayPosClaims
{
    public const string User = "sub";
    public const string Tenant = "tid";
    public const string Device = "did";
    public const string Role = "role";
}

internal sealed class JwtAccessTokenIssuer(IOptions<JwtOptions> options) : IAccessTokenIssuer
{
    private readonly JsonWebTokenHandler _handler = new();

    public (string Token, DateTime ExpiresAt) Issue(User user, Device device, DateTime now)
    {
        var o = options.Value;
        var expires = now.AddMinutes(o.AccessTokenMinutes);
        var token = _handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = o.Issuer,
            Audience = o.Audience,
            IssuedAt = now,
            NotBefore = now,
            Expires = expires,
            SigningCredentials = new SigningCredentials(o.Key(), SecurityAlgorithms.HmacSha256),
            Subject = new ClaimsIdentity(
            [
                new Claim(ZayPosClaims.User, user.Id.ToString()),
                new Claim(ZayPosClaims.Tenant, user.TenantId.ToString()),
                new Claim(ZayPosClaims.Device, device.Id.ToString()),
                new Claim(ZayPosClaims.Role, user.Role == UserRole.Owner ? "owner" : "staff"),
            ]),
        });
        return (token, expires);
    }
}

/// <summary>ASP.NET Core <see cref="PasswordHasher{TUser}"/> (PBKDF2) for 6-digit PINs.</summary>
internal sealed class PinHasher : IPinHasher
{
    private readonly PasswordHasher<User> _hasher = new();

    public string Hash(User user, string pin) => _hasher.HashPassword(user, pin);

    public PinCheck Verify(User user, string hash, string pin) => _hasher.VerifyHashedPassword(user, hash, pin) switch
    {
        PasswordVerificationResult.Success => PinCheck.Success,
        PasswordVerificationResult.SuccessRehashNeeded => PinCheck.SuccessRehashNeeded,
        _ => PinCheck.Failed,
    };
}

/// <summary>v1 dev SMS: writes the message (with the OTP) to the log/console.</summary>
internal sealed class LoggingSmsSender(ILogger<LoggingSmsSender> logger) : ISmsSender
{
    public Task SendAsync(string phone, string message, CancellationToken ct)
    {
        logger.LogWarning("DEV SMS to {Phone}: {Message}", phone, message);
        return Task.CompletedTask;
    }
}
