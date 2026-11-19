using ZayPOS.Application.Auth;

namespace ZayPOS.Api.Endpoints;

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/api/v1/auth")
            .WithTags("Auth")
            .AllowAnonymous(); // rate limited globally, see AuthRateLimiting

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

        // Google sign-in (docs/backend/auth-google.md).
        auth.MapPost("/google/shops", async (GoogleShopsRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.GoogleShopsAsync(req, ct)))
            .Produces<GoogleShopsResponse>();

        auth.MapPost("/google", async (GoogleSignInRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.GoogleSignInAsync(req, ct)))
            .Produces<AuthResponse>();

        auth.MapPost("/google/register", async (GoogleRegisterRequest req, AuthService svc, CancellationToken ct) =>
                Results.Ok(await svc.GoogleRegisterAsync(req, ct)))
            .Produces<AuthResponse>();

        auth.MapPost("/google/pin/reset", async (GoogleResetPinRequest req, AuthService svc, CancellationToken ct) =>
            {
                await svc.GoogleResetPinAsync(req, ct);
                return Results.NoContent();
            })
            .Produces(StatusCodes.Status204NoContent);

        return app;
    }
}
