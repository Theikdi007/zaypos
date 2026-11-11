using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
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
        return services;
    }
}
