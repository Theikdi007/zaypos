using Microsoft.Data.SqlClient;
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

    /// <summary>A dedicated database (the container's default connection string points at master).</summary>
    public string ConnectionString =>
        new SqlConnectionStringBuilder(_container.GetConnectionString()) { InitialCatalog = "ZayPOS" }.ConnectionString;

    /// <summary>Shared API host with a generous rate limit.</summary>
    public ApiFactory Api => _api ??= new ApiFactory(ConnectionString);

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var db = CreateContext(tenantId: null);
        await db.Database.MigrateAsync();
        // Readers don't block on in-flight writers, so the pull test can hold a transaction open
        // while pulling. Recommended for production too (see the STEP 3 notes).
        await db.Database.ExecuteSqlRawAsync("ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE");
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
