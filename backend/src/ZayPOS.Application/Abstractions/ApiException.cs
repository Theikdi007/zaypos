namespace ZayPOS.Application.Abstractions;

/// <summary>A failure that maps 1:1 to a ProblemDetails response with a stable <see cref="Code"/>.</summary>
public class ApiException(int status, string code, string detail, TimeSpan? retryAfter = null) : Exception(detail)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public TimeSpan? RetryAfter { get; } = retryAfter;
}
