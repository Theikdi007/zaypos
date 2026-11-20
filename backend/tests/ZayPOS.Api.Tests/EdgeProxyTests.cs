using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using ZayPOS.Api.Hosting;

namespace ZayPOS.Api.Tests;

/// <summary>The edge-proxy middleware on its own: which requests it believes, and that it always strips its headers.</summary>
public class EdgeProxyMiddlewareTests
{
    private const string Secret = "edge-secret-0123456789-abcdefghijklmnop";
    private const string Next = "edge-secret-NEXT-0123456789-abcdefghijk";
    private static readonly IPAddress Google = IPAddress.Parse("74.125.0.1"); // the TCP peer as Caddy reports it

    private sealed record Seen(IPAddress? Ip, bool Via, bool SecretHeader, bool ClientIpHeader);

    private static async Task<Seen> Run(string? secrets, Action<IHeaderDictionary> headers)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["EdgeProxy:Secrets"] = secrets })
            .Build();
        var services = new ServiceCollection()
            .AddSingleton<IConfiguration>(config)
            .AddSingleton<ILoggerFactory>(NullLoggerFactory.Instance)
            .BuildServiceProvider();
        var app = new ApplicationBuilder(services);
        app.UseEdgeProxyClientIp();
        Seen? seen = null;
        app.Run(http =>
        {
            seen = new Seen(http.Connection.RemoteIpAddress, http.Items.ContainsKey(EdgeProxy.ViaItemKey),
                http.Request.Headers.ContainsKey(EdgeProxy.SecretHeader), http.Request.Headers.ContainsKey(EdgeProxy.ClientIpHeader));
            return Task.CompletedTask;
        });
        var http = new DefaultHttpContext();
        http.Connection.RemoteIpAddress = Google;
        headers(http.Request.Headers);
        await app.Build()(http);
        return seen!;
    }

    [Fact]
    public async Task The_right_secret_makes_the_phone_the_client_and_both_headers_are_removed()
    {
        var seen = await Run(Secret, h => { h[EdgeProxy.SecretHeader] = Secret; h[EdgeProxy.ClientIpHeader] = "203.0.113.9"; });
        seen.Should().Be(new Seen(IPAddress.Parse("203.0.113.9"), true, false, false));
    }

    [Fact]
    public async Task During_a_rotation_both_secrets_are_accepted()
    {
        foreach (var s in new[] { Secret, Next })
        {
            var seen = await Run($"{Secret}, {Next}", h => { h[EdgeProxy.SecretHeader] = s; h[EdgeProxy.ClientIpHeader] = "203.0.113.9"; });
            seen.Ip.Should().Be(IPAddress.Parse("203.0.113.9"));
        }
    }

    [Theory]
    [InlineData("wrong-secret-0123456789-abcdefghijklmnop")]
    [InlineData("")]
    [InlineData("edge-secret-0123456789-abcdefghijklmno")] // one character short
    [InlineData("EDGE-SECRET-0123456789-ABCDEFGHIJKLMNOP")] // case matters
    public async Task A_wrong_secret_changes_nothing_but_the_headers_are_still_removed(string secret)
    {
        var seen = await Run(Secret, h => { h[EdgeProxy.SecretHeader] = secret; h[EdgeProxy.ClientIpHeader] = "203.0.113.9"; });
        seen.Should().Be(new Seen(Google, false, false, false));
    }

    [Fact]
    public async Task Without_configured_secrets_nothing_is_believed_not_even_an_empty_secret()
    {
        foreach (var configured in new string?[] { null, "", " , " })
        {
            var seen = await Run(configured, h => { h[EdgeProxy.SecretHeader] = ""; h[EdgeProxy.ClientIpHeader] = "203.0.113.9"; });
            seen.Should().Be(new Seen(Google, false, false, false));
        }
    }

    [Fact]
    public async Task A_client_ip_header_without_the_secret_is_ignored_and_removed()
    {
        var seen = await Run(Secret, h => h[EdgeProxy.ClientIpHeader] = "203.0.113.9");
        seen.Should().Be(new Seen(Google, false, false, false));
    }

    [Theory]
    [InlineData("not-an-ip")]
    [InlineData("203.0.113.9, 198.51.100.1")]
    [InlineData("")]
    public async Task The_right_secret_with_an_unusable_client_ip_keeps_the_peer(string clientIp)
    {
        var seen = await Run(Secret, h => { h[EdgeProxy.SecretHeader] = Secret; h[EdgeProxy.ClientIpHeader] = clientIp; });
        seen.Should().Be(new Seen(Google, false, false, false));
    }

    [Fact]
    public async Task Repeated_headers_are_not_believed()
    {
        var seen = await Run(Secret, h =>
        {
            h[EdgeProxy.SecretHeader] = new[] { Secret, Secret };
            h[EdgeProxy.ClientIpHeader] = "203.0.113.9";
        });
        seen.Should().Be(new Seen(Google, false, false, false));
    }

    [Theory]
    [InlineData("2001:db8::7", "2001:db8::7")]
    [InlineData("::ffff:203.0.113.9", "203.0.113.9")]
    [InlineData(" 203.0.113.9 ", "203.0.113.9")]
    public async Task IPv6_and_mapped_addresses(string header, string expected)
    {
        var seen = await Run(Secret, h => { h[EdgeProxy.SecretHeader] = Secret; h[EdgeProxy.ClientIpHeader] = header; });
        seen.Ip.Should().Be(IPAddress.Parse(expected));
    }

    [Fact]
    public async Task A_short_configured_secret_refuses_to_start()
    {
        var act = () => Run("too-short", _ => { });
        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*at least 32*");
    }
}

/// <summary>The real pipeline: the per-IP auth limit is per phone behind the proxy, and per peer otherwise.</summary>
[Collection(SqlServerCollection.Name)]
public class EdgeProxyApiTests(SqlServerFixture sql)
{
    private const string Secret = "edge-secret-0123456789-abcdefghijklmnop";
    private static readonly IPAddress Google = IPAddress.Parse("74.125.0.1");

    private static HttpRequestMessage Refresh(string? secret, string clientIp)
    {
        var m = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/refresh")
        {
            Content = JsonContent.Create(new { refreshToken = "garbage" }),
        };
        if (secret is not null) m.Headers.Add(EdgeProxy.SecretHeader, secret);
        m.Headers.Add(EdgeProxy.ClientIpHeader, clientIp);
        return m;
    }

    private ApiFactory Api(string? secrets) => new(sql.ConnectionString, authPerIp: 1, remoteIp: Google,
        settings: new Dictionary<string, string?> { ["EdgeProxy:Secrets"] = secrets });

    [Fact]
    public async Task Behind_the_proxy_every_phone_has_its_own_limit()
    {
        await using var api = Api(Secret);
        var http = api.CreateClient();
        (await http.SendAsync(Refresh(Secret, "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.SendAsync(Refresh(Secret, "203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized,
            "another phone behind the same Google address has its own bucket");
        (await http.SendAsync(Refresh(Secret, "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.TooManyRequests,
            "the first phone's bucket is used up");
    }

    [Theory]
    [InlineData("wrong-secret-0123456789-abcdefghijklmnop")]
    [InlineData(null)]
    public async Task Without_the_right_secret_a_client_cannot_choose_its_bucket(string? sent)
    {
        await using var api = Api(Secret);
        var http = api.CreateClient();
        (await http.SendAsync(Refresh(sent, "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.SendAsync(Refresh(sent, "203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.TooManyRequests,
            "the bucket is the TCP peer's");
    }

    [Fact]
    public async Task With_no_secret_configured_the_headers_are_never_believed()
    {
        await using var api = Api(null);
        var http = api.CreateClient();
        (await http.SendAsync(Refresh("", "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.SendAsync(Refresh("", "203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
    }
}
