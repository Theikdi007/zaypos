using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Api.Tests;

/// <summary>The real API against the test container. SMS is captured instead of logged.</summary>
public sealed class ApiFactory(string connectionString, int authPerMinute = 10_000) : WebApplicationFactory<Program>
{
    /// <summary>Test-only key; the real one lives in user-secrets / env.</summary>
    public const string SigningKey = "test-signing-key-0123456789-abcdefghijklmnopqrstuvwxyz";

    public CapturingSmsSender Sms { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:ZayPOS", connectionString);
        builder.UseSetting("Jwt:SigningKey", SigningKey);
        builder.UseSetting("RateLimiting:AuthPerMinute", authPerMinute.ToString());
        builder.ConfigureTestServices(s =>
        {
            s.RemoveAll<ISmsSender>();
            s.AddSingleton<ISmsSender>(Sms);
        });
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
