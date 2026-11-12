using System.Collections.Concurrent;
using System.Net;
using Microsoft.AspNetCore.Builder;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Api.Tests;

/// <summary>The real API against the test container. SMS is captured instead of logged.</summary>
public sealed class ApiFactory(
    string connectionString,
    int authPerIp = 10_000,
    int authPerPhone = 10_000,
    IPAddress? remoteIp = null,
    Action<IServiceCollection>? services = null,
    IReadOnlyDictionary<string, string?>? settings = null) : WebApplicationFactory<Program>
{
    /// <summary>Test-only key; the real one lives in user-secrets / env.</summary>
    public const string SigningKey = "test-signing-key-0123456789-abcdefghijklmnopqrstuvwxyz";

    public CapturingSmsSender Sms { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:ZayPOS", connectionString);
        builder.UseSetting("Jwt:SigningKey", SigningKey);
        builder.UseSetting("RateLimiting:AuthPerIpPerMinute", authPerIp.ToString());
        builder.UseSetting("RateLimiting:AuthPerPhonePerMinute", authPerPhone.ToString());
        foreach (var (key, value) in settings ?? new Dictionary<string, string?>())
            builder.UseSetting(key, value);
        builder.ConfigureTestServices(s =>
        {
            s.RemoveAll<ISmsSender>();
            s.AddSingleton<ISmsSender>(Sms);
            if (remoteIp is not null) s.AddSingleton<IStartupFilter>(new RemoteIpStartupFilter(remoteIp));
            services?.Invoke(s);
        });
    }

    /// <summary>TestServer has no TCP peer; pretend the request came from <paramref name="ip"/>.</summary>
    private sealed class RemoteIpStartupFilter(IPAddress ip) : IStartupFilter
    {
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
        {
            app.Use((http, nxt) =>
            {
                http.Connection.RemoteIpAddress = ip;
                return nxt(http);
            });
            next(app);
        };
    }
}

public sealed partial class CapturingSmsSender : ISmsSender
{
    private readonly ConcurrentDictionary<string, string> _lastCode = new();
    private readonly ConcurrentDictionary<string, int> _count = new();

    public Task SendAsync(string phone, string message, CancellationToken ct)
    {
        _lastCode[phone] = SixDigits().Match(message).Value;
        _count.AddOrUpdate(phone, 1, (_, n) => n + 1);
        return Task.CompletedTask;
    }

    public string LastCode(string phone) =>
        _lastCode.TryGetValue(phone, out var c) ? c : throw new InvalidOperationException($"No SMS sent to {phone}.");

    public int Count(string phone) => _count.GetValueOrDefault(phone);

    [GeneratedRegex(@"\d{6}")]
    private static partial Regex SixDigits();
}
