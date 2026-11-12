using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace ZayPOS.Infrastructure.Storage;

/// <summary>
/// AWS Signature V4 query-string presigning (S3 / Cloudflare R2). Signs the given headers
/// (always <c>host</c>) with an unsigned payload. No SDK: the algorithm is small and fixed.
/// https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
/// </summary>
public static class SigV4Presigner
{
    public static Uri Presign(
        string method, Uri url, string region, string service, string accessKeyId, string secretAccessKey,
        DateTime now, TimeSpan expires, IReadOnlyDictionary<string, string>? signedHeaders = null)
    {
        var seconds = (long)expires.TotalSeconds;
        if (seconds is < 1 or > 604_800) throw new ArgumentOutOfRangeException(nameof(expires), "1 s .. 7 days.");

        var amzDate = now.ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);
        var date = amzDate[..8];
        var scope = $"{date}/{region}/{service}/aws4_request";

        var headers = new SortedDictionary<string, string>(StringComparer.Ordinal) { ["host"] = url.IsDefaultPort ? url.Host : $"{url.Host}:{url.Port}" };
        foreach (var (k, v) in signedHeaders ?? new Dictionary<string, string>())
            headers[k.ToLowerInvariant()] = v.Trim();
        var signedNames = string.Join(';', headers.Keys);

        var query = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256",
            ["X-Amz-Credential"] = $"{accessKeyId}/{scope}",
            ["X-Amz-Date"] = amzDate,
            ["X-Amz-Expires"] = seconds.ToString(CultureInfo.InvariantCulture),
            ["X-Amz-SignedHeaders"] = signedNames,
        };
        var canonicalQuery = string.Join('&', query.Select(kv => $"{Encode(kv.Key)}={Encode(kv.Value)}"));

        var canonicalRequest = string.Join('\n',
            method,
            CanonicalPath(url.AbsolutePath),
            canonicalQuery,
            string.Concat(headers.Select(kv => $"{kv.Key}:{kv.Value}\n")),
            signedNames,
            "UNSIGNED-PAYLOAD");

        var stringToSign = string.Join('\n', "AWS4-HMAC-SHA256", amzDate, scope, Hex(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRequest))));

        var key = Hmac(Encoding.UTF8.GetBytes("AWS4" + secretAccessKey), date);
        key = Hmac(key, region);
        key = Hmac(key, service);
        key = Hmac(key, "aws4_request");
        var signature = Hex(Hmac(key, stringToSign));

        return new UriBuilder(url) { Query = $"{canonicalQuery}&X-Amz-Signature={signature}" }.Uri;
    }

    /// <summary>S3 encodes each path segment once (no double encoding), keeping '/'.</summary>
    private static string CanonicalPath(string absolutePath)
    {
        var decoded = Uri.UnescapeDataString(absolutePath);
        return string.Join('/', decoded.Split('/').Select(Encode));
    }

    /// <summary>RFC 3986: only A-Z a-z 0-9 - _ . ~ stay literal; uppercase hex.</summary>
    public static string Encode(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var b in Encoding.UTF8.GetBytes(value))
        {
            var c = (char)b;
            if (char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.' or '~') sb.Append(c);
            else sb.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }

    private static byte[] Hmac(byte[] key, string data) => HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(data));

    private static string Hex(byte[] bytes) => Convert.ToHexStringLower(bytes);
}
