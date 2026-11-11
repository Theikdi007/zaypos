namespace ZayPOS.Application.Abstractions;

/// <summary>SMS provider. v1 dev implementation only logs the message.</summary>
public interface ISmsSender
{
    Task SendAsync(string phone, string message, CancellationToken ct);
}
