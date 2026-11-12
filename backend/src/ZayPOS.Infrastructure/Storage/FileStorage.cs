using System.Net;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Infrastructure.Storage;

/// <summary>
/// Config section "Storage:R2". All four values set → Cloudflare R2; otherwise file features answer 503.
/// Keep the secret in user-secrets / environment, never in appsettings.json.
/// </summary>
public sealed class R2Options
{
    public const string Section = "Storage:R2";
    public string AccountId { get; set; } = "";
    public string AccessKeyId { get; set; } = "";
    public string SecretAccessKey { get; set; } = "";
    public string Bucket { get; set; } = "";
    /// <summary>Optional override (e.g. a jurisdiction endpoint); default https://{AccountId}.r2.cloudflarestorage.com.</summary>
    public string? Endpoint { get; set; }

    public bool IsConfigured =>
        AccountId.Length > 0 && AccessKeyId.Length > 0 && SecretAccessKey.Length > 0 && Bucket.Length > 0;

    public Uri BaseUri => new(string.IsNullOrWhiteSpace(Endpoint) ? $"https://{AccountId}.r2.cloudflarestorage.com" : Endpoint.TrimEnd('/'));
}

/// <summary>Cloudflare R2 (S3 API, region "auto"), path-style: https://{account}.r2.cloudflarestorage.com/{bucket}/{key}.</summary>
internal sealed class R2FileStorage(IOptions<R2Options> options, TimeProvider clock, HttpClient http) : IFileStorage
{
    private const string Region = "auto";
    private const string Service = "s3";

    public PresignedUpload PresignUpload(string key, string contentType, long sizeBytes, TimeSpan validFor)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var headers = new Dictionary<string, string>
        {
            ["Content-Type"] = contentType,
            ["Content-Length"] = sizeBytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
        };
        var url = Sign("PUT", key, now, validFor, headers);
        return new PresignedUpload(key, url, "PUT", headers, now.Add(validFor));
    }

    public Uri PresignDownload(string key, TimeSpan validFor) => Sign("GET", key, clock.GetUtcNow().UtcDateTime, validFor);

    public async Task<bool> ExistsAsync(string key, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Head, Sign("HEAD", key, clock.GetUtcNow().UtcDateTime, TimeSpan.FromMinutes(1)));
        using var res = await http.SendAsync(req, ct);
        if (res.StatusCode == HttpStatusCode.NotFound) return false;
        res.EnsureSuccessStatusCode();
        return true;
    }

    private Uri Sign(string method, string key, DateTime now, TimeSpan validFor, IReadOnlyDictionary<string, string>? headers = null)
    {
        var o = options.Value;
        var path = "/" + SigV4Presigner.Encode(o.Bucket) + "/" + string.Join('/', key.Split('/').Select(SigV4Presigner.Encode));
        var url = new Uri(o.BaseUri, path);
        return SigV4Presigner.Presign(method, url, Region, Service, o.AccessKeyId, o.SecretAccessKey, now, validFor, headers);
    }
}

/// <summary>Storage not configured (local dev without R2): screenshot features answer 503.</summary>
internal sealed class NotConfiguredFileStorage : IFileStorage
{
    private static ApiException NotConfigured() =>
        new(503, "storage_not_configured", "File storage is not configured on this server (Storage:R2).");

    public PresignedUpload PresignUpload(string key, string contentType, long sizeBytes, TimeSpan validFor) => throw NotConfigured();
    public Uri PresignDownload(string key, TimeSpan validFor) => throw NotConfigured();
    public Task<bool> ExistsAsync(string key, CancellationToken ct) => throw NotConfigured();
}
