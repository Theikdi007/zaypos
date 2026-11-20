using System.Text;
using System.Text.Json;
using ZayPOS.Application.Auth;

namespace ZayPOS.Api.Tests;

/// <summary>
/// Stands in for Google in API tests. <see cref="Token"/> builds an unsigned JWT whose payload carries
/// sub/email (so the rate limiter's per-account partition sees a real-looking token); this fake trusts
/// it. "bad" → google_token_invalid, "down" → google_unavailable. The real signature/iss/aud/exp checks
/// are covered by GoogleIdTokenVerifierTests.
/// </summary>
public sealed class FakeGoogleVerifier : IGoogleIdTokenVerifier
{
    public const string ClientId = "test-web.apps.googleusercontent.com";

    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    public int Calls { get; private set; }

    /// <summary>A fresh Google account id (digits, like Google's).</summary>
    public static string NewSubject() => "1" + Interlocked.Increment(ref _seq).ToString("D20");

    public static string Token(string subject, string? email = "owner@example.com")
    {
        static string B64(object o) => Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(o))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var payload = email is null ? (object)new { sub = subject } : new { sub = subject, email };
        return $"{B64(new { alg = "RS256", typ = "JWT" })}.{B64(payload)}.fake-signature";
    }

    public Task<GoogleIdentity> VerifyAsync(string? idToken, CancellationToken ct)
    {
        Calls++;
        if (idToken == "down") throw AuthException.GoogleUnavailable();
        var parts = idToken?.Split('.') ?? [];
        if (parts.Length != 3 || parts[2] != "fake-signature") throw AuthException.GoogleTokenInvalid();
        var json = parts[1].Replace('-', '+').Replace('_', '/');
        json = json.PadRight(json.Length + (4 - json.Length % 4) % 4, '=');
        using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(json)));
        var sub = doc.RootElement.GetProperty("sub").GetString()!;
        var email = doc.RootElement.TryGetProperty("email", out var e) ? e.GetString() : null;
        return Task.FromResult(new GoogleIdentity(sub, email));
    }
}
