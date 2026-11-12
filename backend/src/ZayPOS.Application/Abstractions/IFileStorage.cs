namespace ZayPOS.Application.Abstractions;

/// <summary>A browser/app-side upload: PUT the bytes to <see cref="Url"/> with exactly these headers.</summary>
public sealed record PresignedUpload(string Key, Uri Url, string Method, IReadOnlyDictionary<string, string> Headers, DateTime ExpiresAt);

/// <summary>
/// Object storage for user files (subscription screenshots). Production: Cloudflare R2 via
/// S3-compatible presigned URLs, so file bytes never pass through the API.
/// </summary>
public interface IFileStorage
{
    /// <summary>The upload URL only accepts this content type and exactly <paramref name="sizeBytes"/> bytes.</summary>
    PresignedUpload PresignUpload(string key, string contentType, long sizeBytes, TimeSpan validFor);

    /// <summary>A short-lived GET URL (admin review).</summary>
    Uri PresignDownload(string key, TimeSpan validFor);

    Task<bool> ExistsAsync(string key, CancellationToken ct);
}
