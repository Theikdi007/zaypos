using System.Globalization;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using ZayPOS.Application.Auth;

namespace ZayPOS.Api.Auth;

/// <summary>Turns <see cref="AuthException"/> and bad JSON into ProblemDetails with a stable "code".</summary>
public sealed class AuthExceptionHandler(IProblemDetailsService problems) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken ct)
    {
        var (status, code, detail, retryAfter) = exception switch
        {
            AuthException a => (a.Status, a.Code, a.Message, a.RetryAfter),
            BadHttpRequestException b => (400, "validation", b.Message, (TimeSpan?)null),
            _ => (0, "", "", null),
        };
        if (status == 0) return false;

        http.Response.StatusCode = status;
        if (retryAfter is { } wait)
            http.Response.Headers.RetryAfter = Math.Ceiling(wait.TotalSeconds).ToString(CultureInfo.InvariantCulture);

        return await problems.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            Exception = exception,
            ProblemDetails = new ProblemDetails
            {
                Status = status,
                Title = code,
                Detail = detail,
                Extensions = { ["code"] = code },
            },
        });
    }
}
