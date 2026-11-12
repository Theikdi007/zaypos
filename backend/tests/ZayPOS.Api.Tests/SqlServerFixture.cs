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
        // The migrations alone must leave the database ready (incl. READ_COMMITTED_SNAPSHOT,
        // which the pull test relies on); nothing here may patch the schema.
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
