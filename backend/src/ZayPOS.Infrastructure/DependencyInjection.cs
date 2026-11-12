using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Account;
using ZayPOS.Application.Catalog;
using ZayPOS.Application.Subscription;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Sync;
using ZayPOS.Infrastructure.Auth;
using ZayPOS.Infrastructure.Persistence;
using ZayPOS.Infrastructure.Storage;
using ZayPOS.Infrastructure.Sync;

namespace ZayPOS.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("ZayPOS")
            ?? throw new InvalidOperationException("Connection string 'ZayPOS' is not configured.");

        services.AddDbContext<ZayPosDbContext>(o => o.UseSqlServer(connectionString,
            sql => sql.MigrationsHistoryTable("__EFMigrationsHistory", "dbo")));

        services.AddOptions<JwtOptions>()
            .Bind(configuration.GetSection(JwtOptions.Section))
            .Validate(o => Encoding.UTF8.GetByteCount(o.SigningKey) >= JwtOptions.MinKeyBytes,
                $"Jwt:SigningKey must be at least {JwtOptions.MinKeyBytes} bytes. In development run: " +
                "dotnet user-secrets set Jwt:SigningKey \"$(openssl rand -base64 48)\" --project src/ZayPOS.Api")
            .ValidateOnStart();

        services.AddScoped<IAppDb>(sp => sp.GetRequiredService<ZayPosDbContext>());
        services.AddSingleton<IDbErrors, SqlServerDbErrors>();
        services.AddScoped<SyncPushService>();
        services.AddScoped<SyncIssueService>();
        services.AddScoped<ISyncPull, SyncPullService>();

        services.TryAddSingleton(TimeProvider.System);
        services.AddScoped<IAuthRepository, AuthRepository>();
        services.AddSingleton<IPinHasher, PinHasher>();
        services.AddSingleton<IAccessTokenIssuer, JwtAccessTokenIssuer>();
        services.TryAddSingleton<ISmsSender, LoggingSmsSender>();
        services.AddScoped<AuthService>();

        services.AddScoped<AccountService>();
        services.AddScoped<PresetCatalogService>();
        services.AddScoped<SubscriptionService>();
        services.AddOptions<SubscriptionOptions>().Bind(configuration.GetSection(SubscriptionOptions.Section));
        AddFileStorage(services, configuration);
        return services;
    }

    /// <summary>R2 only when fully configured (Storage:R2); otherwise screenshot endpoints answer 503.</summary>
    private static void AddFileStorage(IServiceCollection services, IConfiguration configuration)
    {
        var section = configuration.GetSection(R2Options.Section);
        services.AddOptions<R2Options>().Bind(section);
        if (section.Get<R2Options>() is { IsConfigured: true })
            services.TryAddSingleton<IFileStorage>(sp => new R2FileStorage(
                sp.GetRequiredService<IOptions<R2Options>>(), sp.GetRequiredService<TimeProvider>(),
                new HttpClient { Timeout = TimeSpan.FromSeconds(10) }));
        else
            services.TryAddSingleton<IFileStorage, NotConfiguredFileStorage>();
    }
}
