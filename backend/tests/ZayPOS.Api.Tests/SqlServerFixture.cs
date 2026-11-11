using Microsoft.EntityFrameworkCore;
using Testcontainers.MsSql;
using ZayPOS.Application.Abstractions;
using ZayPOS.Infrastructure.Persistence;

namespace ZayPOS.Api.Tests;

/// <summary>One real SQL Server 2022 container per test collection, migrated once.</summary>
public sealed class SqlServerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();

    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var db = CreateContext(tenantId: null);
        await db.Database.MigrateAsync();
    }

    public Task DisposeAsync() => _container.DisposeAsync().AsTask();

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
