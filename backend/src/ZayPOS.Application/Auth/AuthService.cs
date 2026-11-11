using System.Security.Cryptography;
using System.Text;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Auth;

/// <summary>README §4: OTP, register, login, refresh with rotation, PIN reset, lockout.</summary>
public sealed class AuthService(
    IAuthRepository repo,
    IPinHasher pins,
    IAccessTokenIssuer accessTokens,
    ISmsSender sms,
    TimeProvider clock)
{
    private DateTime Now => TruncateMs(clock.GetUtcNow().UtcDateTime);

    // ---------------------------------------------------------------- OTP

    public async Task<OtpResponse> RequestOtpAsync(OtpRequest req, CancellationToken ct)
    {
        var phone = RequirePhone(req.Phone);
        var now = Now;
        var registered = await repo.FindUserByPhoneAsync(phone, ct) is not null;

        if (req.Purpose == OtpPurpose.Register && registered)
            throw new AuthException(409, "phone_registered", "This phone already has a shop. Sign in instead.");

        var expiresAt = now + AuthRules.OtpLifetime;
        // Reset for an unknown phone: answer exactly like a real send, but send nothing.
        if (req.Purpose == OtpPurpose.Reset && !registered)
            return new OtpResponse(expiresAt);

        var sent = await repo.CountOtpsSinceAsync(phone, now.AddHours(-1), ct);
        if (sent >= AuthRules.OtpPerPhonePerHour)
            throw new AuthException(429, "otp_rate_limited", "Too many codes. Try again later.", TimeSpan.FromHours(1));

        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        repo.Add(new OtpChallenge
        {
            Id = Guid.CreateVersion7(),
            Phone = phone,
            CodeHash = HashOtp(phone, req.Purpose, code),
            Purpose = req.Purpose,
            ExpiresAt = expiresAt,
            CreatedAt = now,
        });
        await repo.SaveChangesAsync(ct);
        await sms.SendAsync(phone, $"ZayPOS code: {code}", ct);
        return new OtpResponse(expiresAt);
    }

    // ---------------------------------------------------------------- Register

    public async Task<AuthResponse> RegisterAsync(RegisterRequest req, CancellationToken ct)
    {
        var phone = RequirePhone(req.Phone);
        RequirePin(req.Pin);
        var shopName = RequireText(req.ShopName, "shopName", 120);
        var township = OptionalText(req.Township, "township", 80);
        var deviceName = RequireDevice(req.Device);
        if (!ShopTemplates.Exists(req.TemplateId ?? ""))
            throw AuthException.Validation($"Unknown templateId. Use one of: {string.Join(", ", ShopTemplates.Ids)}.");

        if (await repo.FindUserByPhoneAsync(phone, ct) is not null)
            throw new AuthException(409, "phone_registered", "This phone already has a shop. Sign in instead.");

        var otp = await ConsumeOtpAsync(phone, OtpPurpose.Register, req.Otp, ct);

        if (await repo.FindDeviceAsync(req.Device.Id, ct) is not null)
            throw DeviceConflict();

        var now = Now;
        var tenant = new Tenant
        {
            Id = Guid.CreateVersion7(), Name = shopName, TemplateId = req.TemplateId!, Township = township,
            Phone = phone, Plan = TenantPlan.Free, CreatedAt = now, UpdatedAt = now,
        };
        var user = new User
        {
            Id = Guid.CreateVersion7(), TenantId = tenant.Id, Phone = phone,
            Name = shopName.Length > 80 ? shopName[..80] : shopName,
            Role = UserRole.Owner, CreatedAt = now, UpdatedAt = now,
        };
        user.PinHash = pins.Hash(user, req.Pin);
        var device = new Device
        {
            Id = req.Device.Id, TenantId = tenant.Id, Code = DeviceCodes.ForIndex(0), Name = deviceName,
            CreatedAt = now, UpdatedAt = now,
        };

        repo.Add(tenant);
        repo.Add(user);
        foreach (var (key, enabled) in ShopTemplates.FeaturesFor(tenant.TemplateId))
            repo.Add(new TenantFeature { TenantId = tenant.Id, FeatureKey = key, Enabled = enabled, UpdatedAt = now });
        repo.Add(device);
        var (refresh, token) = NewRefreshToken(user, device, now);
        repo.Add(token);
        otp.ConsumedAt = now;

        try
        {
            await repo.SaveChangesAsync(ct);
        }
        catch (UniqueViolationException e) when (e.Involves("UX_Users_Phone"))
        {
            throw new AuthException(409, "phone_registered", "This phone already has a shop. Sign in instead.");
        }

        return Respond(user, tenant, device, refresh, token, now);
    }

    // ---------------------------------------------------------------- Login

    public async Task<AuthResponse> LoginAsync(LoginRequest req, CancellationToken ct)
    {
        var phone = PhoneNumbers.Normalize(req.Phone) ?? throw AuthException.InvalidCredentials();
        var deviceName = RequireDevice(req.Device);
        var user = await repo.FindUserByPhoneAsync(phone, ct) ?? throw AuthException.InvalidCredentials();
        var now = Now;

        if (user.LockedUntil is { } until && until > now)
            throw Locked(until - now);

        var check = Pins.IsValid(req.Pin) ? pins.Verify(user, user.PinHash, req.Pin) : PinCheck.Failed;
        if (check == PinCheck.Failed)
        {
            user.FailedPinCount++;
            user.UpdatedAt = now;
            var lockedNow = user.FailedPinCount >= AuthRules.PinMaxFailures;
            if (lockedNow)
            {
                user.LockedUntil = now + AuthRules.PinLockout;
                user.FailedPinCount = 0;
            }
            await repo.SaveChangesAsync(ct);
            throw lockedNow ? Locked(AuthRules.PinLockout) : AuthException.InvalidCredentials();
        }

        if (check == PinCheck.SuccessRehashNeeded) user.PinHash = pins.Hash(user, req.Pin);
        if (user.FailedPinCount != 0 || user.LockedUntil is not null || check == PinCheck.SuccessRehashNeeded)
        {
            user.FailedPinCount = 0;
            user.LockedUntil = null;
            user.UpdatedAt = now;
        }

        var tenant = await repo.FindTenantAsync(user.TenantId, ct) ?? throw AuthException.InvalidCredentials();
        var device = await repo.FindDeviceAsync(req.Device.Id, ct);
        if (device is not null)
        {
            if (device.TenantId != user.TenantId) throw DeviceConflict();
            if (device.DeletedAt is not null) throw DeviceRevoked();
            if (deviceName is not null && device.Name != deviceName)
            {
                device.Name = deviceName;
                device.UpdatedAt = now;
            }
            // Re-login on the same phone: old sessions of this device end.
            await repo.RevokeRefreshTokensAsync(user.Id, device.Id, now, ct);
            var (refresh, token) = NewRefreshToken(user, device, now);
            repo.Add(token);
            await repo.SaveChangesAsync(ct);
            return Respond(user, tenant, device, refresh, token, now);
        }

        // New phone → next free code. Two phones logging in at once can race for
        // the same code; UX_Devices_Code catches it and we take the next one.
        for (var attempt = 1; ; attempt++)
        {
            var codes = await repo.DeviceCodesAsync(user.TenantId, ct);
            var newDevice = new Device
            {
                Id = req.Device.Id, TenantId = user.TenantId, Code = DeviceCodes.NextFree(codes), Name = deviceName,
                CreatedAt = now, UpdatedAt = now,
            };
            var (refresh, token) = NewRefreshToken(user, newDevice, now);
            repo.Add(newDevice);
            repo.Add(token);
            try
            {
                await repo.SaveChangesAsync(ct);
                return Respond(user, tenant, newDevice, refresh, token, now);
            }
            catch (UniqueViolationException e) when (e.Involves("UX_Devices_Code") && attempt < 5)
            {
                repo.Discard(token);
                repo.Discard(newDevice);
            }
            catch (UniqueViolationException e) when (e.Involves("PK_Devices"))
            {
                throw DeviceConflict();
            }
        }
    }

    // ---------------------------------------------------------------- Refresh

    public async Task<AuthResponse> RefreshAsync(RefreshRequest req, CancellationToken ct)
    {
        var hash = HashRefreshToken(req.RefreshToken) ?? throw AuthException.InvalidRefreshToken();
        var current = await repo.FindRefreshTokenAsync(hash, ct) ?? throw AuthException.InvalidRefreshToken();
        var now = Now;

        if (current.RevokedAt is not null)
        {
            // A revoked token came back: it was stolen or replayed. End every session on that device.
            await repo.RevokeRefreshTokensAsync(current.UserId, current.DeviceId, now, ct);
            throw AuthException.InvalidRefreshToken();
        }
        if (current.ExpiresAt <= now) throw AuthException.InvalidRefreshToken();

        var user = await repo.FindUserAsync(current.UserId, ct);
        var device = await repo.FindDeviceAsync(current.DeviceId, ct);
        if (user is null || user.DeletedAt is not null || device is null) throw AuthException.InvalidRefreshToken();
        if (device.DeletedAt is not null) throw DeviceRevoked();
        var tenant = await repo.FindTenantAsync(user.TenantId, ct) ?? throw AuthException.InvalidRefreshToken();

        var (refresh, next) = NewRefreshToken(user, device, now);
        await using var tx = await repo.BeginTransactionAsync(ct);
        if (!await repo.TryRevokeRefreshTokenAsync(current.Id, next.Id, now, ct))
            throw AuthException.InvalidRefreshToken(); // lost a race with a concurrent refresh
        repo.Add(next);
        await repo.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        return Respond(user, tenant, device, refresh, next, now);
    }

    // ---------------------------------------------------------------- PIN reset

    public async Task ResetPinAsync(ResetPinRequest req, CancellationToken ct)
    {
        var phone = RequirePhone(req.Phone);
        RequirePin(req.NewPin);
        var user = await repo.FindUserByPhoneAsync(phone, ct) ?? throw AuthException.OtpInvalid();
        var otp = await ConsumeOtpAsync(phone, OtpPurpose.Reset, req.Otp, ct);
        var now = Now;

        user.PinHash = pins.Hash(user, req.NewPin);
        user.FailedPinCount = 0;
        user.LockedUntil = null;
        user.UpdatedAt = now;
        otp.ConsumedAt = now;

        await using var tx = await repo.BeginTransactionAsync(ct);
        await repo.RevokeRefreshTokensAsync(user.Id, deviceId: null, now, ct);
        await repo.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    // ---------------------------------------------------------------- helpers

    /// <summary>Checks the code; a wrong code costs one attempt (saved even though the request fails).</summary>
    private async Task<OtpChallenge> ConsumeOtpAsync(string phone, OtpPurpose purpose, string? code, CancellationToken ct)
    {
        var challenge = await repo.FindOpenOtpAsync(phone, purpose, Now, AuthRules.OtpMaxAttempts, ct)
            ?? throw AuthException.OtpInvalid();

        var given = HashOtp(phone, purpose, code?.Trim() ?? "");
        if (!CryptographicOperations.FixedTimeEquals(given, challenge.CodeHash))
        {
            challenge.Attempts++;
            await repo.SaveChangesAsync(ct);
            throw AuthException.OtpInvalid();
        }
        return challenge;
    }

    private (string Token, RefreshToken Row) NewRefreshToken(User user, Device device, DateTime now)
    {
        var raw = Base64Url(RandomNumberGenerator.GetBytes(32));
        return (raw, new RefreshToken
        {
            Id = Guid.CreateVersion7(),
            UserId = user.Id,
            DeviceId = device.Id,
            TokenHash = SHA256.HashData(Encoding.ASCII.GetBytes(raw)),
            ExpiresAt = now + AuthRules.RefreshTokenLifetime,
            CreatedAt = now,
        });
    }

    private AuthResponse Respond(User user, Tenant tenant, Device device, string refresh, RefreshToken row, DateTime now)
    {
        var (access, accessExpires) = accessTokens.Issue(user, device, now);
        return new AuthResponse(
            access, accessExpires, refresh, row.ExpiresAt,
            new AuthUser(user.Id, user.Name, user.Role),
            new AuthTenant(tenant.Id, tenant.Name, tenant.TemplateId, tenant.Plan),
            new AuthDevice(device.Id, device.Code, device.LastSeq));
    }

    private static byte[] HashOtp(string phone, OtpPurpose purpose, string code) =>
        SHA256.HashData(Encoding.UTF8.GetBytes($"{phone}:{purpose}:{code}"));

    private static byte[]? HashRefreshToken(string? raw) =>
        string.IsNullOrWhiteSpace(raw) || raw.Length > 100 ? null : SHA256.HashData(Encoding.ASCII.GetBytes(raw.Trim()));

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    /// <summary>datetime2(3) keeps milliseconds; match it so values round-trip exactly.</summary>
    private static DateTime TruncateMs(DateTime t) => new(t.Ticks - t.Ticks % TimeSpan.TicksPerMillisecond, DateTimeKind.Utc);

    private static string RequirePhone(string? phone) =>
        PhoneNumbers.Normalize(phone) ?? throw AuthException.Validation("phone must be a Myanmar mobile number (09… or +959…).");

    private static void RequirePin(string? pin)
    {
        if (!Pins.IsValid(pin)) throw AuthException.Validation("PIN must be exactly 6 digits.");
    }

    private static string RequireText(string? value, string field, int max)
    {
        var s = value?.Trim();
        if (string.IsNullOrEmpty(s)) throw AuthException.Validation($"{field} is required.");
        if (s.Length > max) throw AuthException.Validation($"{field} must be at most {max} characters.");
        return s;
    }

    private static string? OptionalText(string? value, string field, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : RequireText(value, field, max);

    private static string? RequireDevice(DeviceInfo? device)
    {
        if (device is null || device.Id == Guid.Empty) throw AuthException.Validation("device.id is required.");
        return OptionalText(device.Name, "device.name", 60);
    }

    private static AuthException Locked(TimeSpan retryAfter) =>
        new(423, "pin_locked", "Too many wrong PINs. Try again later or reset the PIN.", retryAfter);

    private static AuthException DeviceConflict() =>
        new(409, "device_conflict", "This device id belongs to another shop. Reinstall the app.");

    private static AuthException DeviceRevoked() =>
        new(403, "device_revoked", "The owner removed this device. Reinstall the app to sign in again.");
}
