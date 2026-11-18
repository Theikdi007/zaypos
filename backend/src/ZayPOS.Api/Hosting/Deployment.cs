using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using ZayPOS.Infrastructure.Persistence;
using ZayPOS.Infrastructure.Sms;

namespace ZayPOS.Api.Hosting;

/// <summary>`dotnet ZayPOS.Api.dll migrate`: the deploy step that runs before the API starts.</summary>
public static class MigrateCommand
{
    public static bool IsInvoked(string[] args) => args is ["migrate", ..];

    /// <summary>
    /// Reads ConnectionStrings:ZayPOSAdmin (sa, only given to this one-shot container) and
    /// ConnectionStrings:ZayPOS (the API's own login, created/updated here). Exit code 0 = ready.
    /// </summary>
    public static async Task<int> RunAsync(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args[1..]);
        using var host = builder.Build();
        var log = host.Services.GetRequiredService<ILoggerFactory>().CreateLogger("ZayPOS.Migrate");
        var config = host.Services.GetRequiredService<IConfiguration>();
        var admin = config.GetConnectionString("ZayPOSAdmin");
        var app = config.GetConnectionString("ZayPOS");
        if (string.IsNullOrWhiteSpace(admin) || string.IsNullOrWhiteSpace(app))
        {
            log.LogCritical("migrate needs ConnectionStrings:ZayPOSAdmin (admin/sa) and ConnectionStrings:ZayPOS (the API login)");
            return 2;
        }
        try
        {
            await DatabaseMigrator.MigrateAsync(admin, app, log);
            return 0;
        }
        catch (Exception e) when (e is SqlException or InvalidOperationException)
        {
            // The message is safe to log: SqlClient never puts passwords in exception text.
            log.LogCritical("migrate failed: {Error}", e.Message);
            return 1;
        }
    }
}

public static class DeploymentExtensions
{
    /// <summary>Startup gate: refuse to serve on a database that is missing migrations.</summary>
    public static async Task EnsureDatabaseMigratedAsync(this WebApplication app)
    {
        if (!app.Configuration.GetValue("Database:CheckMigrationsOnStartup", true)) return;
        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZayPosDbContext>();
        var log = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("ZayPOS.Startup");
        var pending = await DatabaseMigrator.PendingMigrationsAsync(db, log,
            TimeSpan.FromSeconds(app.Configuration.GetValue("Database:StartupWaitSeconds", 60)));
        if (pending.Count == 0) return;

        var error = new PendingMigrationsException(pending);
        log.LogCritical("{Error}", error.Message);
        throw error;
    }

    /// <summary>
    /// Production must be configured safely or not start at all: a known SMS provider (SmsPoh with a
    /// token, or Console on purpose), an API login that is not sa, and HTTPS required.
    /// </summary>
    public static void ValidateProductionConfig(this WebApplicationBuilder builder)
    {
        if (!builder.Environment.IsProduction()) return;
        var config = builder.Configuration;
        var errors = new List<string>();

        var sms = config.GetSection(SmsOptions.Section).Get<SmsOptions>() ?? new SmsOptions();
        if (sms.UsesSmsPoh)
        {
            if (!sms.SmsPoh.HasCredentials)
                errors.Add("SMSPoh credential missing: set Sms:SmsPoh:ApiKey + Sms:SmsPoh:ApiSecret (or Sms:SmsPoh:Token).");
        }
        else if (!sms.UsesLog)
            errors.Add($"Sms:Provider must be '{SmsOptions.SmsPohProvider}' or '{SmsOptions.ConsoleProvider}' (is '{sms.Provider}').");

        var cs = config.GetConnectionString("ZayPOS");
        if (!string.IsNullOrWhiteSpace(cs))
        {
            var user = new SqlConnectionStringBuilder(cs).UserID;
            if (string.Equals(user, "sa", StringComparison.OrdinalIgnoreCase) || string.IsNullOrEmpty(user))
                errors.Add("ConnectionStrings:ZayPOS must use the API's own SQL login, not sa.");
        }

        if (!config.GetValue("Https:Require", false))
            errors.Add("Https:Require must be true in Production.");

        if (errors.Count > 0)
            throw new InvalidOperationException("Unsafe production configuration:\n - " + string.Join("\n - ", errors));
    }

    /// <summary>Production with Sms:Provider=Console: allowed (before SMSPoh is ready), but never quietly.</summary>
    public static void WarnAboutConsoleSms(this WebApplication app)
    {
        if (!app.Environment.IsProduction()) return;
        var sms = app.Configuration.GetSection(SmsOptions.Section).Get<SmsOptions>() ?? new SmsOptions();
        if (!sms.UsesLog) return;
        app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("ZayPOS.Startup").LogCritical(
            "Sms:Provider={Provider} in Production: OTP codes are NOT sent by SMS, they are written to this log " +
            "(anyone who can read the server's logs can sign in to any shop). Switch to SmsPoh before real shops register.",
            sms.Provider);
    }

    public static IServiceCollection AddZayPosHealthChecks(this IServiceCollection services)
    {
        services.AddHealthChecks().AddCheck<DatabaseHealthCheck>("database", tags: ["ready"]);
        return services;
    }

    /// <summary>GET /health: 200 {"status":"healthy","checks":{"database":"healthy"}} or 503. No details, no secrets.</summary>
    public static IEndpointConventionBuilder MapZayPosHealth(this IEndpointRouteBuilder app) =>
        app.MapHealthChecks("/health", new HealthCheckOptions
        {
            ResultStatusCodes =
            {
                [HealthStatus.Healthy] = StatusCodes.Status200OK,
                [HealthStatus.Degraded] = StatusCodes.Status200OK,
                [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable,
            },
            ResponseWriter = async (http, report) =>
            {
                http.Response.ContentType = "application/json";
                http.Response.Headers.CacheControl = "no-store";
                await JsonSerializer.SerializeAsync(http.Response.Body, new
                {
                    status = Name(report.Status),
                    checks = report.Entries.ToDictionary(e => e.Key, e => Name(e.Value.Status)),
                });
            },
        }).DisableRateLimiting();

    private static string Name(HealthStatus s) => s.ToString().ToLowerInvariant();

    /// <summary>
    /// Https:Require: a request that did not arrive over HTTPS (after forwarded headers from the
    /// trusted proxy) gets 400 https_required. No redirect: a redirect would already have leaked
    /// the request. Loopback is exempt (the container health check).
    /// </summary>
    public static IApplicationBuilder UseRequireHttps(this IApplicationBuilder app) => app.Use(async (http, next) =>
    {
        if (http.Request.IsHttps || http.Connection.RemoteIpAddress is { } ip && IPAddress.IsLoopback(ip))
        {
            await next();
            return;
        }
        http.Response.StatusCode = StatusCodes.Status400BadRequest;
        var problems = http.RequestServices.GetRequiredService<IProblemDetailsService>();
        await problems.WriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            ProblemDetails = new ProblemDetails
            {
                Status = 400, Title = "https_required", Detail = "Use https://.",
                Extensions = { ["code"] = "https_required" },
            },
        });
    });
}

/// <summary>Can the API reach its database with its own login? Exception text is never returned.</summary>
internal sealed class DatabaseHealthCheck(ZayPosDbContext db) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            return await db.Database.CanConnectAsync(timeout.Token)
                ? HealthCheckResult.Healthy()
                : HealthCheckResult.Unhealthy();
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return HealthCheckResult.Unhealthy();
        }
    }
}
