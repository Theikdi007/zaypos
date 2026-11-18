using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Infrastructure.Sms;

/// <summary>
/// "Sms" config section. <c>Provider</c>: <c>Log</c> or its alias <c>Console</c> (the code goes to the
/// log: dev, and production only until SMSPoh is ready) or <c>SmsPoh</c>. Production refuses any other
/// value (a typo must not silently fall back to logging codes) and warns loudly at every start when the
/// code goes to the log (see the API's DeploymentExtensions).
/// </summary>
public sealed class SmsOptions
{
    public const string Section = "Sms";
    public const string LogProvider = "Log";
    public const string ConsoleProvider = "Console";
    public const string SmsPohProvider = "SmsPoh";

    public string Provider { get; set; } = LogProvider;
    public SmsPohOptions SmsPoh { get; set; } = new();

    public bool UsesSmsPoh => string.Equals(Provider, SmsPohProvider, StringComparison.OrdinalIgnoreCase);

    public bool UsesLog => string.Equals(Provider, LogProvider, StringComparison.OrdinalIgnoreCase)
                           || string.Equals(Provider, ConsoleProvider, StringComparison.OrdinalIgnoreCase);
}

public sealed class SmsPohOptions
{
    /// <summary>SMSPoh v3 REST endpoint.</summary>
    public string Endpoint { get; set; } = "https://v3.smspoh.com/api/rest/send";

    /// <summary>v3 API credential (dashboard → Accounts &amp; Security → API Credentials). Env only, never appsettings.</summary>
    public string ApiKey { get; set; } = "";

    /// <summary>The credential's secret. Env only, never appsettings.</summary>
    public string ApiSecret { get; set; } = "";

    /// <summary>Alternative to ApiKey + ApiSecret: the ready Bearer value, base64("APIKey:APISecret").</summary>
    public string Token { get; set; } = "";

    /// <summary>Sender ID registered with SMSPoh (case-sensitive). Empty = account default.</summary>
    public string Sender { get; set; } = "";

    /// <summary>true = SMSPoh accepts the message but does not deliver or charge it (smoke tests).</summary>
    public bool Test { get; set; }

    public bool HasCredentials =>
        !string.IsNullOrWhiteSpace(Token) || (!string.IsNullOrWhiteSpace(ApiKey) && !string.IsNullOrWhiteSpace(ApiSecret));

    /// <summary>The Bearer value per the v3 spec: base64("APIKey:APISecret"), or <see cref="Token"/> when given.</summary>
    public string BearerToken() => !string.IsNullOrWhiteSpace(Token)
        ? Token.Trim()
        : Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes($"{ApiKey.Trim()}:{ApiSecret.Trim()}"));
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
/// SMSPoh (Myanmar) v3 REST API: POST {Endpoint}, <c>Authorization: Bearer base64("APIKey:APISecret")</c>,
/// JSON { to, message, from, test } (<c>test</c> is a JSON boolean per the v3 spec: true = accepted, not
/// delivered, not charged). Never logs the message text (it holds the OTP) or the token; SMSPoh's reply
/// is logged with every 4+ digit run masked. A failed send answers 503 sms_unavailable.
/// </summary>
public sealed partial class SmsPohSmsSender(IOptions<SmsOptions> options, HttpClient http, ILogger<SmsPohSmsSender> logger) : ISmsSender
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
                ["test"] = o.Test,
            }.Where(kv => kv.Value is not "").ToDictionary()),
        };
        var bearer = o.BearerToken();
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);

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
            var reply = await SafeReplyAsync(response, [bearer, o.ApiKey, o.ApiSecret], ct);
            if (response.IsSuccessStatusCode)
            {
                logger.LogInformation("SMS {Outcome} to {Phone} via SMSPoh (test={Test}): HTTP {Status} {Reply}",
                    o.Test ? "accepted in TEST mode (not delivered)" : "sent", Mask(phone), o.Test, (int)response.StatusCode, reply);
                return;
            }
            logger.LogError("SMSPoh refused SMS to {Phone}: HTTP {Status} {Reply}", Mask(phone), (int)response.StatusCode, reply);
            throw Unavailable();
        }
    }

    private static ApiException Unavailable() =>
        new(503, "sms_unavailable", "Could not send the SMS. Try again shortly.", TimeSpan.FromSeconds(30));

    /// <summary>
    /// SMSPoh's reply for the log: at most 300 characters, whitespace collapsed, the credential removed if it is
    /// ever echoed, and every run of 4+ digits masked (phone numbers, the OTP in an echoed message).
    /// </summary>
    internal static async Task<string> SafeReplyAsync(HttpResponseMessage response, string[] secrets, CancellationToken ct)
    {
        string body;
        try
        {
            body = await response.Content.ReadAsStringAsync(ct);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException)
        {
            return "(no body)";
        }
        return Sanitize(body, secrets);
    }

    internal static string Sanitize(string body, params string[] secrets)
    {
        foreach (var secret in secrets.Where(x => x.Trim().Length >= 4))
            body = body.Replace(secret.Trim(), "[token]", StringComparison.Ordinal);
        body = Digits().Replace(Whitespace().Replace(body, " ").Trim(), "####");
        return body.Length <= 300 ? body : body[..300] + "…";
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"\d{4,}")]
    private static partial System.Text.RegularExpressions.Regex Digits();

    [System.Text.RegularExpressions.GeneratedRegex(@"\s+")]
    private static partial System.Text.RegularExpressions.Regex Whitespace();

    /// <summary>+959123456789 → +9591234***89 (enough to correlate, not a full number in the logs).</summary>
    internal static string Mask(string phone) =>
        phone.Length <= 6 ? "***" : phone[..^5] + "***" + phone[^2..];
}
