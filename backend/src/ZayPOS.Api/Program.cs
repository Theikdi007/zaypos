using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using ZayPOS.Api;
using ZayPOS.Api.Auth;
using ZayPOS.Api.Endpoints;
using ZayPOS.Api.Hosting;
using ZayPOS.Application.Abstractions;
using ZayPOS.Infrastructure;
using ZayPOS.Infrastructure.Auth;

// Deploy step: `dotnet ZayPOS.Api.dll migrate` applies EF migrations and the API's SQL login, then exits.
if (MigrateCommand.IsInvoked(args)) return await MigrateCommand.RunAsync(args);

var builder = WebApplication.CreateBuilder(args);
builder.ValidateProductionConfig();

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentTenant, HttpCurrentTenant>();
builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ApiExceptionHandler>();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// JWT bearer. The key is read lazily from validated JwtOptions (user-secrets in dev).
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<JwtOptions>>((bearer, jwt) =>
    {
        var o = jwt.Value;
        bearer.MapInboundClaims = false; // keep "sub", "tid", "did", "role" as-is
        bearer.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = o.Issuer,
            ValidAudience = o.Audience,
            IssuerSigningKey = o.Key(),
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = ZayPosClaims.User,
            RoleClaimType = ZayPosClaims.Role,
        };
    });
builder.Services.AddAuthorization(o =>
    o.AddPolicy(Caller.OwnerPolicy, p => p.RequireAuthenticatedUser().RequireClaim(ZayPosClaims.Role, "owner")));
builder.Services.AddMemoryCache();
builder.Services.AddZayPosHealthChecks();

// /auth/*: per client IP + per phone. The OTP limit (3/hour/phone) also lives in AuthService.
builder.Services.AddAuthRateLimiting(builder.Configuration);
var useForwarding = builder.Services.AddCloudflareForwarding(builder.Configuration, builder.Environment);

var app = builder.Build();
await app.EnsureDatabaseMigratedAsync(); // refuses to start (clear log line) if migrations are pending
app.WarnAboutConsoleSms();

if (useForwarding) app.UseForwardedHeaders(); // before anything reads RemoteIpAddress or the scheme
app.UseExceptionHandler();
if (app.Configuration.GetValue("Https:Require", false))
{
    app.UseRequireHttps();
    app.UseHsts();
}
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthentication();
app.UseAuthorization();
app.UseAuthPhonePartition();
app.UseRateLimiter();

app.MapGet("/api/v1/health", () => Results.Ok(new { status = "ok" })); // liveness only (the app uses it)
app.MapZayPosHealth(); // GET /health: also checks the database
app.MapAuthEndpoints();
app.MapSyncEndpoints();
app.MapAccountEndpoints();

await app.RunAsync();
return 0;

public partial class Program;
