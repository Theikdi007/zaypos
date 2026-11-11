using ZayPOS.Application.Auth;

namespace ZayPOS.Api.Endpoints;

public static class AuthEndpoints
{
    public const string RateLimitPolicy = "auth";

    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/api/v1/auth")
            .WithTags("Auth")
            .AllowAnonymous()
            .RequireRateLimiting(RateLimitPolicy);

        auth.MapPost("/otp", async (OtpRequest req, AuthService svc, CancellationToken ct) =>
                Results.Accepted(value: await svc.RequestOtpAsync(req, ct)))
            .Produces<OtpResponse>(StatusCodes.Status202Accepted);

        auth.MapPost("/register", async (RegisterRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.RegisterAsync(req, ct)))
            .Produces<AuthResponse>();

        auth.MapPost("/login", async (LoginRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.LoginAsync(req, ct)))
            .Produces<AuthResponse>();

        auth.MapPost("/refresh", async (RefreshRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.RefreshAsync(req, ct)))
            .Produces<AuthResponse>();

        auth.MapPost("/pin/reset", async (ResetPinRequest req, AuthService svc, CancellationToken ct) =>
            {
                await svc.ResetPinAsync(req, ct);
                return Results.NoContent();
            })
            .Produces(StatusCodes.Status204NoContent);

        return app;
    }
}
