using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using ZayPOS.Api.Auth;
using ZayPOS.Api.Endpoints;
using ZayPOS.Application.Abstractions;
using ZayPOS.Infrastructure;
using ZayPOS.Infrastructure.Auth;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentTenant, HttpCurrentTenant>();
builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<AuthExceptionHandler>();
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
builder.Services.AddAuthorization();

// /auth/*: per client IP + per phone. The OTP limit (3/hour/phone) also lives in AuthService.
builder.Services.AddAuthRateLimiting(builder.Configuration);
var useForwarding = builder.Services.AddCloudflareForwarding(builder.Configuration, builder.Environment);

var app = builder.Build();

if (useForwarding) app.UseForwardedHeaders(); // before anything reads RemoteIpAddress
app.UseExceptionHandler();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthentication();
app.UseAuthorization();
app.UseAuthPhonePartition();
app.UseRateLimiter();

app.MapGet("/api/v1/health", () => Results.Ok(new { status = "ok" }));
app.MapAuthEndpoints();

app.Run();

public partial class Program;
