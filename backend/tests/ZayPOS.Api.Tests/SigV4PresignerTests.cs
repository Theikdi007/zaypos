using FluentAssertions;
using ZayPOS.Infrastructure.Storage;

namespace ZayPOS.Api.Tests;

public class SigV4PresignerTests
{
    /// <summary>The worked example in the AWS S3 docs ("Authenticating Requests: Using Query Parameters").</summary>
    [Fact]
    public void Matches_the_aws_documentation_example()
    {
        var url = SigV4Presigner.Presign(
            "GET", new Uri("https://examplebucket.s3.amazonaws.com/test.txt"), "us-east-1", "s3",
            "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            new DateTime(2013, 5, 24, 0, 0, 0, DateTimeKind.Utc), TimeSpan.FromDays(1));

        url.AbsoluteUri.Should().Be(
            "https://examplebucket.s3.amazonaws.com/test.txt" +
            "?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
            "&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" +
            "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host" +
            "&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404");
    }

    [Fact]
    public void Signed_headers_change_the_signature()
    {
        Uri Sign(string type) => SigV4Presigner.Presign("PUT", new Uri("https://a.r2.cloudflarestorage.com/b/k.png"), "auto", "s3",
            "id", "secret", new DateTime(2026, 11, 12, 0, 0, 0, DateTimeKind.Utc), TimeSpan.FromMinutes(10),
            new Dictionary<string, string> { ["Content-Type"] = type });

        Sign("image/png").Should().NotBe(Sign("image/jpeg"));
    }
}
