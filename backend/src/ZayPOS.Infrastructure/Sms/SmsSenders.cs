using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Infrastructure.Sms;

/// <summary>
/// "Sms" config section. <c>Provider</c>: <c>Log</c> (dev: the code goes to the log) or <c>SmsPoh</c>.
/// Production refuses to start with anything but SmsPoh (see the API's ProductionChecks).
/// </summary>
public sealed class SmsOptions
{
    public const string Section = "Sms";
    public const string LogProvider = "Log";
    public const string SmsPohProvider = "SmsPoh";

    public string Provider { get; set; } = LogProvider;
    public SmsPohOptions SmsPoh { get; set; } = new();

    public bool UsesSmsPoh => string.Equals(Provider, SmsPohProvider, StringComparison.OrdinalIgnoreCase);
}

public sealed class SmsPohOptions
{
    /// <summary>SMSPoh v3 REST endpoint.</summary>
    public string Endpoint { get; set; } = "https://v3.smspoh.com/api/rest/send";

    /// <summary>Bearer token. For v3 keys: base64("key:secret"). Secret: env only, never appsettings.</summary>
    public string Token { get; set; } = "";

    /// <summary>Sender ID registered with SMSPoh (case-sensitive). Empty = account default.</summary>
    public string Sender { get; set; } = "";

    /// <summary>true = SMSPoh accepts the message but does not deliver it (smoke tests).</summary>
    public bool Test { get; set; }
}

/// <summary>v1 dev SMS: writes the message (with the OTP) to the log/console.</summary>
internal sealed class LoggingSmsSender(ILogger<LoggingSmsSender> logger) : ISmsSender
{
    public Task SendAsync(string phone, string message, CancellationToken ct)
    {
        logger.LogWarning("DEV SMS to {Phone}: {Message}", phone, message);
        return Task.CompletedTask;
    }
}

/// <summary>
/// SMSPoh (Myanmar) REST API: POST {Endpoint} with a Bearer token, JSON { to, message, from }.
/// Never logs the message text (it holds the OTP). A failed send answers 503 sms_unavailable.
/// </summary>
public sealed class SmsPohSmsSender(IOptions<SmsOptions> options, HttpClient http, ILogger<SmsPohSmsSender> logger) : ISmsSender
{
    public async Task SendAsync(string phone, string message, CancellationToken ct)
    {
        var o = options.Value.SmsPoh;
        using var request = new HttpRequestMessage(HttpMethod.Post, o.Endpoint)
        {
            Content = JsonContent.Create(new Dictionary<string, object>
            {
                ["to"] = phone,
                ["message"] = message,
                ["from"] = o.Sender,
                ["test"] = o.Test ? 1 : 0,
            }.Where(kv => kv.Value is not "").ToDictionary()),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", o.Token);

        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, ct);
        }
        catch (Exception e) when ((e is HttpRequestException or TaskCanceledException) && !ct.IsCancellationRequested)
        {
            logger.LogError("SMSPoh unreachable sending to {Phone}: {Error}", Mask(phone), e.GetType().Name);
            throw Unavailable();
        }

        using (response)
        {
            if (response.IsSuccessStatusCode)
            {
                logger.LogInformation("SMS sent to {Phone} via SMSPoh", Mask(phone));
                return;
            }
            logger.LogError("SMSPoh refused SMS to {Phone}: HTTP {Status}", Mask(phone), (int)response.StatusCode);
            throw Unavailable();
        }
    }

    private static ApiException Unavailable() =>
        new(503, "sms_unavailable", "Could not send the SMS. Try again shortly.", TimeSpan.FromSeconds(30));

    /// <summary>+959123456789 → +9591234***89 (enough to correlate, not a full number in the logs).</summary>
    internal static string Mask(string phone) =>
        phone.Length <= 6 ? "***" : phone[..^5] + "***" + phone[^2..];
}
