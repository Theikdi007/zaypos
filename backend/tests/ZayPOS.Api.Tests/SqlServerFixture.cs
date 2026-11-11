using Microsoft.EntityFrameworkCore;
using Testcontainers.MsSql;
using ZayPOS.Application.Abstractions;
using ZayPOS.Infrastructure.Persistence;

namespace ZayPOS.Api.Tests;

/// <summary>One real SQL Server 2022 container per test run, migrated once, plus the API on top of it.</summary>
public sealed class SqlServerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();
    private ApiFactory? _api;

    public string ConnectionString => _container.GetConnectionString();

    /// <summary>Shared API host with a generous rate limit.</summary>
    public ApiFactory Api => _api ??= new ApiFactory(ConnectionString);

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var db = CreateContext(tenantId: null);
        await db.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        if (_api is not null) await _api.DisposeAsync();
        await _container.DisposeAsync();
    }

    public ZayPosDbContext CreateContext(Guid? tenantId) =>
        new(new DbContextOptionsBuilder<ZayPosDbContext>().UseSqlServer(ConnectionString).Options,
            new FixedTenant(tenantId));

    private sealed record FixedTenant(Guid? TenantId) : ICurrentTenant;
}

[CollectionDefinition(Name)]
public sealed class SqlServerCollection : ICollectionFixture<SqlServerFixture>
{
    public const string Name = "sqlserver";
}
