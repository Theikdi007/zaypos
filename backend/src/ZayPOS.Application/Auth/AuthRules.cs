using System.Text.RegularExpressions;

namespace ZayPOS.Application.Auth;

/// <summary>Numbers from README §4.</summary>
public static class AuthRules
{
    public static readonly TimeSpan OtpLifetime = TimeSpan.FromMinutes(5);
    public const int OtpMaxAttempts = 5;
    public const int OtpPerPhonePerHour = 3;
    public const int PinMaxFailures = 5;
    public static readonly TimeSpan PinLockout = TimeSpan.FromMinutes(15);
    public static readonly TimeSpan RefreshTokenLifetime = TimeSpan.FromDays(90);
    /// <summary>A just-rotated token presented again within this window is a retry, not theft.</summary>
    public static readonly TimeSpan RefreshRetryGrace = TimeSpan.FromMinutes(2);
    /// <summary>Shops one Google account may own (stops one account from minting shops).</summary>
    public const int GoogleShopsPerAccount = 10;
}

public static partial class PhoneNumbers
{
    /// <summary>
    /// Myanmar mobile number → E.164 ("09 7xx xxx 102" → "+9597xxxxxx102").
    /// Accepts 09…, 959… and +959… with spaces/dashes/dots and Myanmar digits (၀-၉), the same rules as the
    /// app's phoneKey/normalizeMmPhone (BUG-34). Returns null when invalid.
    /// </summary>
    public static string? Normalize(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var s = Separators().Replace(ToAsciiDigits(input.Trim()), "");
        if (s.StartsWith("+959")) s = s[4..];
        else if (s.StartsWith("959")) s = s[3..];
        else if (s.StartsWith("09")) s = s[2..];
        else return null;
        return Subscriber().IsMatch(s) ? "+959" + s : null;
    }

    /// <summary>Myanmar digits ၀-၉ (U+1040–U+1049) → 0-9.</summary>
    public static string ToAsciiDigits(string s) =>
        string.Create(s.Length, s, (span, src) =>
        {
            for (var i = 0; i < src.Length; i++)
                span[i] = src[i] is >= '\u1040' and <= '\u1049' ? (char)('0' + (src[i] - '\u1040')) : src[i];
        });

    [GeneratedRegex(@"[\s\-().]")]
    private static partial Regex Separators();

    [GeneratedRegex(@"^\d{7,9}$")]
    private static partial Regex Subscriber();
}

public static partial class Pins
{
    /// <summary>The app's PIN pad takes exactly 6 digits.</summary>
    public static bool IsValid(string? pin) => pin is not null && SixDigits().IsMatch(pin);

    [GeneratedRegex(@"^\d{6}$")]
    private static partial Regex SixDigits();
}

/// <summary>Device codes A, B, … Z, AA, AB, … ZZZ (bijective base-26, max 3 letters = varchar(3)).</summary>
public static class DeviceCodes
{
    public const int MaxIndex = 26 + 26 * 26 + 26 * 26 * 26; // A..ZZZ

    /// <summary>0 → "A", 25 → "Z", 26 → "AA".</summary>
    public static string ForIndex(int index)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(index, MaxIndex);
        var n = index + 1;
        var chars = new Stack<char>();
        while (n > 0)
        {
            n--;
            chars.Push((char)('A' + n % 26));
            n /= 26;
        }
        return new string(chars.ToArray());
    }

    /// <summary>First code not in <paramref name="taken"/>.</summary>
    public static string NextFree(IEnumerable<string> taken)
    {
        var used = new HashSet<string>(taken, StringComparer.Ordinal);
        for (var i = 0; i < MaxIndex; i++)
        {
            var code = ForIndex(i);
            if (!used.Contains(code)) return code;
        }
        throw new InvalidOperationException("No device codes left for this shop.");
    }
}
