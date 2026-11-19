using System.Security.Cryptography;
using System.Text;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Text.Zawgyi;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Auth;

/// <summary>
/// README §4 + docs/backend/auth-google.md: Google sign-in, OTP (behind <see cref="AuthSettings.OtpEnabled"/>),
/// register, login, refresh with rotation, PIN reset, lockout. Google and OTP only answer "who is this
/// user"; shop creation, the PIN check, devices and tokens are one shared path.
/// </summary>
public sealed class AuthService(
    IAuthRepository repo,
    IPinHasher pins,
    IAccessTokenIssuer accessTokens,
    ISmsSender sms,
    IGoogleIdTokenVerifier google,
    AuthSettings settings,
    TimeProvider clock)
{
    private DateTime Now => TruncateMs(clock.GetUtcNow().UtcDateTime);

    // ---------------------------------------------------------------- OTP

    public async Task<OtpResponse> RequestOtpAsync(OtpRequest req, CancellationToken ct)
    {
        RequireOtpEnabled();
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
        RequireOtpEnabled();
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
        otp.ConsumedAt = now;
        try
        {
            return await CreateShopAsync(shopName, req.TemplateId!, township, ownerPhone: phone, loginPhone: phone,
                googleIdentity: null, req.Pin, req.Device, deviceName, now, ct);
        }
        catch (UniqueViolationException e) when (e.Involves("UX_Users_Phone"))
        {
            throw new AuthException(409, "phone_registered", "This phone already has a shop. Sign in instead.");
        }
    }

    /// <summary>
    /// Tenant + owner user + template features + device A + first refresh token, in one save.
    /// <paramref name="loginPhone"/> is a verified phone (OTP) or null; <paramref name="ownerPhone"/> is the
    /// shop's contact number (verified only when it came through OTP).
    /// </summary>
    private async Task<AuthResponse> CreateShopAsync(
        string shopName, string templateId, string? township, string ownerPhone, string? loginPhone,
        GoogleIdentity? googleIdentity, string pin, DeviceInfo deviceInfo, string? deviceName, DateTime now,
        CancellationToken ct)
    {
        var tenant = new Tenant
        {
            Id = Guid.CreateVersion7(), Name = shopName, TemplateId = templateId, Township = township,
            Phone = ownerPhone, Plan = TenantPlan.Free, CreatedAt = now, UpdatedAt = now,
        };
        var user = new User
        {
            Id = Guid.CreateVersion7(), TenantId = tenant.Id, Phone = loginPhone,
            GoogleSubject = googleIdentity?.Subject, GoogleEmail = Email(googleIdentity),
            Name = shopName.Length > 80 ? shopName[..80] : shopName,
            Role = UserRole.Owner, CreatedAt = now, UpdatedAt = now,
        };
        user.PinHash = pins.Hash(user, pin);
        var device = new Device
        {
            Id = deviceInfo.Id, TenantId = tenant.Id, Code = DeviceCodes.ForIndex(0), Name = deviceName,
            CreatedAt = now, UpdatedAt = now,
        };

        repo.Add(tenant);
        repo.Add(user);
        foreach (var (key, enabled) in ShopTemplates.FeaturesFor(tenant.TemplateId))
            repo.Add(new TenantFeature { TenantId = tenant.Id, FeatureKey = key, Enabled = enabled, UpdatedAt = now });
        repo.Add(device);
        var (refresh, token) = NewRefreshToken(user, device, now);
        repo.Add(token);

        try
        {
            await repo.SaveChangesAsync(ct);
        }
        catch (UniqueViolationException e) when (e.Involves("PK_Devices"))
        {
            throw DeviceConflict();
        }

        return Respond(user, tenant, device, refresh, token, now);
    }

    // ---------------------------------------------------------------- Login

    public async Task<AuthResponse> LoginAsync(LoginRequest req, CancellationToken ct)
    {
        var phone = PhoneNumbers.Normalize(req.Phone) ?? throw AuthException.InvalidCredentials();
        var deviceName = RequireDevice(req.Device);
        var user = await repo.FindUserByPhoneAsync(phone, ct);
        if (user is null) throw UnknownPhone(req.Pin);
        return await SignInAsync(user, req.Pin, req.Device, deviceName, onPinVerified: null, ct);
    }

    /// <summary>
    /// The shared sign-in once "who" is known: lockout, PIN check (5 wrong → 15 min), then this device
    /// (same device = its old sessions end; new device = next free code) and fresh tokens.
    /// <paramref name="onPinVerified"/> runs after a right PIN, before anything is saved (Google: remember
    /// the email, or link the account); it may throw to refuse.
    /// </summary>
    private async Task<AuthResponse> SignInAsync(
        User user, string? pin, DeviceInfo deviceInfo, string? deviceName, Action<User>? onPinVerified, CancellationToken ct)
    {
        var now = Now;

        if (user.LockedUntil is { } until && until > now)
            throw Locked(until - now);

        var check = Pins.IsValid(pin) ? pins.Verify(user, user.PinHash, pin!) : PinCheck.Failed;
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

        if (check == PinCheck.SuccessRehashNeeded) user.PinHash = pins.Hash(user, pin!);
        if (user.FailedPinCount != 0 || user.LockedUntil is not null || check == PinCheck.SuccessRehashNeeded)
        {
            user.FailedPinCount = 0;
            user.LockedUntil = null;
            user.UpdatedAt = now;
        }
        onPinVerified?.Invoke(user);

        var tenant = await repo.FindTenantAsync(user.TenantId, ct) ?? throw AuthException.InvalidCredentials();
        var device = await repo.FindDeviceAsync(deviceInfo.Id, ct);
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
                Id = deviceInfo.Id, TenantId = user.TenantId, Code = DeviceCodes.NextFree(codes), Name = deviceName,
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

        // Re-decide from fresh DB state if a concurrent refresh wins the race for the same token.
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            var presented = await repo.FindRefreshTokenAsync(hash, ct) ?? throw AuthException.InvalidRefreshToken();
            var now = Now;

            RefreshToken rotate;
            if (presented.RevokedAt is null)
            {
                if (presented.ExpiresAt <= now) throw AuthException.InvalidRefreshToken();
                rotate = presented;
            }
            else
            {
                rotate = await GraceRetryTargetAsync(presented, now, ct);
            }

            var user = await repo.FindUserAsync(rotate.UserId, ct);
            var device = await repo.FindDeviceAsync(rotate.DeviceId, ct);
            if (user is null || user.DeletedAt is not null || device is null) throw AuthException.InvalidRefreshToken();
            if (device.DeletedAt is not null) throw DeviceRevoked();
            var tenant = await repo.FindTenantAsync(user.TenantId, ct) ?? throw AuthException.InvalidRefreshToken();

            var (refresh, next) = NewRefreshToken(user, device, now);
            await using var tx = await repo.BeginTransactionAsync(ct);
            if (!await repo.TryRevokeRefreshTokenAsync(rotate.Id, next.Id, now, ct))
                continue; // someone rotated it first: look again (usually ends in the grace path)
            repo.Add(next);
            await repo.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);

            return Respond(user, tenant, device, refresh, next, now);
        }
        throw AuthException.InvalidRefreshToken();
    }

    /// <summary>
    /// A revoked token came back. If it was rotated less than <see cref="AuthRules.RefreshRetryGrace"/> ago
    /// and its replacement was never used, the phone simply lost the response (flaky network) or sent two
    /// refreshes at once: rotate the replacement instead. Anything else is replay → end the device's sessions.
    /// </summary>
    private async Task<RefreshToken> GraceRetryTargetAsync(RefreshToken presented, DateTime now, CancellationToken ct)
    {
        if (presented.ReplacedById is { } replacementId && now - presented.RevokedAt < AuthRules.RefreshRetryGrace)
        {
            var replacement = await repo.FindRefreshTokenByIdAsync(replacementId, ct);
            if (replacement is { RevokedAt: null } && replacement.ExpiresAt > now)
                return replacement;
        }

        await repo.RevokeRefreshTokensAsync(presented.UserId, presented.DeviceId, now, ct);
        throw AuthException.InvalidRefreshToken();
    }

    // ---------------------------------------------------------------- PIN reset

    public async Task ResetPinAsync(ResetPinRequest req, CancellationToken ct)
    {
        RequireOtpEnabled();
        var phone = RequirePhone(req.Phone);
        RequirePin(req.NewPin);
        var user = await repo.FindUserByPhoneAsync(phone, ct) ?? throw AuthException.OtpInvalid();
        var otp = await ConsumeOtpAsync(phone, OtpPurpose.Reset, req.Otp, ct);
        otp.ConsumedAt = Now;
        await SetPinAsync(user, req.NewPin, ct);
    }

    /// <summary>New PIN, lockout cleared, and every session of the user (all devices) ends.</summary>
    private async Task SetPinAsync(User user, string newPin, CancellationToken ct)
    {
        var now = Now;
        user.PinHash = pins.Hash(user, newPin);
        user.FailedPinCount = 0;
        user.LockedUntil = null;
        user.UpdatedAt = now;

        await using var tx = await repo.BeginTransactionAsync(ct);
        await repo.RevokeRefreshTokensAsync(user.Id, deviceId: null, now, ct);
        await repo.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    // ---------------------------------------------------------------- Google (docs/backend/auth-google.md)

    /// <summary>"Who is this user": the shops this Google account can sign in to.</summary>
    public async Task<GoogleShopsResponse> GoogleShopsAsync(GoogleShopsRequest req, CancellationToken ct)
    {
        var id = await google.VerifyAsync(req.IdToken, ct);
        var mine = await repo.FindGoogleUsersAsync(id.Subject, ct);
        return new GoogleShopsResponse(
            Email(id),
            mine.Select(r => new GoogleShop(r.Tenant.Id, r.Tenant.Name, r.Tenant.TemplateId, r.User.Role)).ToList());
    }

    /// <summary>
    /// Sign in on this phone: a shop of this Google account (tenantId) + its PIN, or a shop registered by
    /// phone before Google (phone + PIN, exactly like /login), which links the Google account to it.
    /// </summary>
    public async Task<AuthResponse> GoogleSignInAsync(GoogleSignInRequest req, CancellationToken ct)
    {
        var deviceName = RequireDevice(req.Device);
        var hasPhone = !string.IsNullOrWhiteSpace(req.Phone);
        if (req.TenantId is not null && hasPhone) throw AuthException.Validation("Send tenantId or phone, not both.");
        if (req.TenantId is null && !hasPhone) throw AuthException.Validation("tenantId (or phone, to link a shop) is required.");

        var id = await google.VerifyAsync(req.IdToken, ct);
        var mine = await repo.FindGoogleUsersAsync(id.Subject, ct);

        if (req.TenantId is { } tenantId)
        {
            var user = mine.FirstOrDefault(r => r.Tenant.Id == tenantId).User ?? throw AuthException.ShopNotFound();
            return await SignInAsync(user, req.Pin, req.Device, deviceName, u => RememberEmail(u, id), ct);
        }

        var phone = PhoneNumbers.Normalize(req.Phone) ?? throw AuthException.InvalidCredentials();
        var legacy = await repo.FindUserByPhoneAsync(phone, ct);
        if (legacy is null) throw UnknownPhone(req.Pin);
        return await SignInAsync(legacy, req.Pin, req.Device, deviceName, u => Link(u, id, mine), ct);
    }

    /// <summary>Find-or-create's "create": a new shop owned by this Google account.</summary>
    public async Task<AuthResponse> GoogleRegisterAsync(GoogleRegisterRequest req, CancellationToken ct)
    {
        RequirePin(req.Pin);
        var shopName = RequireText(req.ShopName, "shopName", 120);
        var township = OptionalText(req.Township, "township", 80);
        var ownerPhone = PhoneNumbers.Normalize(req.OwnerPhone)
            ?? throw AuthException.Validation("ownerPhone must be a Myanmar mobile number (09… or +959…).");
        var deviceName = RequireDevice(req.Device);
        if (!ShopTemplates.Exists(req.TemplateId ?? ""))
            throw AuthException.Validation($"Unknown templateId. Use one of: {string.Join(", ", ShopTemplates.Ids)}.");

        var id = await google.VerifyAsync(req.IdToken, ct);
        var mine = await repo.FindGoogleUsersAsync(id.Subject, ct);
        if (mine.Count >= AuthRules.GoogleShopsPerAccount) throw ShopLimit();
        if (await repo.FindDeviceAsync(req.Device.Id, ct) is not null) throw DeviceConflict();

        return await CreateShopAsync(shopName, req.TemplateId!, township, ownerPhone, loginPhone: null,
            id, req.Pin, req.Device, deviceName, Now, ct);
    }

    /// <summary>Forgotten PIN: the Google account proves who it is (instead of an SMS code).</summary>
    public async Task GoogleResetPinAsync(GoogleResetPinRequest req, CancellationToken ct)
    {
        RequirePin(req.NewPin);
        var id = await google.VerifyAsync(req.IdToken, ct);
        var mine = await repo.FindGoogleUsersAsync(id.Subject, ct);
        var user = mine.FirstOrDefault(r => r.Tenant.Id == req.TenantId).User ?? throw AuthException.ShopNotFound();
        RememberEmail(user, id);
        await SetPinAsync(user, req.NewPin, ct);
    }

    private void RememberEmail(User user, GoogleIdentity id)
    {
        var email = Email(id);
        if (email is null || user.GoogleEmail == email) return;
        user.GoogleEmail = email;
        user.UpdatedAt = Now;
    }

    /// <summary>Attaches the Google account to a phone-registered user (after its PIN was right).</summary>
    private void Link(User user, GoogleIdentity id, IReadOnlyList<(User User, Tenant Tenant)> mine)
    {
        if (user.GoogleSubject == id.Subject)
        {
            RememberEmail(user, id);
            return;
        }
        if (user.GoogleSubject is not null)
            throw new AuthException(409, "google_linked_elsewhere",
                "This shop is already linked to another Google account. Sign in with that account.");
        if (mine.Any(r => r.Tenant.Id == user.TenantId))
            throw new AuthException(409, "google_linked_elsewhere", "This Google account already has a user in this shop.");
        if (mine.Count >= AuthRules.GoogleShopsPerAccount) throw ShopLimit();
        user.GoogleSubject = id.Subject;
        user.GoogleEmail = Email(id);
        user.UpdatedAt = Now;
    }

    /// <summary>nvarchar(320): a longer "email" is not a real address; keep the row valid.</summary>
    private static string? Email(GoogleIdentity? id) =>
        id?.Email is { Length: > 0 and <= 320 } e ? e : null;

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
        // Zawgyi-typed shop / township / device names are stored as Unicode (BUG-52).
        var s = MyanmarText.NormalizeToUnicode(value?.Trim());
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

    private void RequireOtpEnabled()
    {
        if (!settings.OtpEnabled) throw AuthException.OtpDisabled();
    }

    /// <summary>Same PBKDF2 cost as a real user, so response time does not reveal which phones exist.</summary>
    private AuthException UnknownPhone(string? pin)
    {
        if (Pins.IsValid(pin)) pins.VerifyDummy(pin!);
        return AuthException.InvalidCredentials();
    }

    private static AuthException ShopLimit() =>
        new(409, "google_shop_limit", $"One Google account can have at most {AuthRules.GoogleShopsPerAccount} shops.");

    private static AuthException Locked(TimeSpan retryAfter) =>
        new(423, "pin_locked", "Too many wrong PINs. Try again later or reset the PIN.", retryAfter);

    private static AuthException DeviceConflict() =>
        new(409, "device_conflict", "This device id belongs to another shop. Reinstall the app.");

    private static AuthException DeviceRevoked() =>
        new(403, "device_revoked", "The owner removed this device. Reinstall the app to sign in again.");
}
