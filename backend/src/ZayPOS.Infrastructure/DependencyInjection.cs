using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Auth;
using ZayPOS.Infrastructure.Auth;
using ZayPOS.Infrastructure.Persistence;

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

        services.TryAddSingleton(TimeProvider.System);
        services.AddScoped<IAuthRepository, AuthRepository>();
        services.AddSingleton<IPinHasher, PinHasher>();
        services.AddSingleton<IAccessTokenIssuer, JwtAccessTokenIssuer>();
        services.TryAddSingleton<ISmsSender, LoggingSmsSender>();
        services.AddScoped<AuthService>();
        return services;
    }
}
