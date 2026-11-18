using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Infrastructure.Persistence;

/// <summary>Thrown at API startup when the database is behind the code. The message says what to run.</summary>
public sealed class PendingMigrationsException(IReadOnlyList<string> pending) : Exception(
    $"Database has {pending.Count} pending EF migration(s): {string.Join(", ", pending)}. " +
    "The API refuses to start on an out-of-date schema. Apply them first with the migrate step " +
    "(production: `docker compose -f docker-compose.prod.yml run --rm migrate`, see docs/deploy/runbook.md; " +
    "development: `dotnet ef database update --project src/ZayPOS.Infrastructure --startup-project src/ZayPOS.Api`).")
{
    public IReadOnlyList<string> Pending { get; } = pending;
}

/// <summary>
/// Deploy-time database work, run by `ZayPOS.Api migrate` with an admin (sa) connection:
/// create the database if missing, apply pending migrations, and create/update the API's own
/// SQL login with only db_datareader + db_datawriter (no DDL, not sa).
/// </summary>
public static partial class DatabaseMigrator
{
    public static async Task MigrateAsync(string adminConnectionString, string appConnectionString, ILogger log, CancellationToken ct = default)
    {
        var admin = new SqlConnectionStringBuilder(adminConnectionString);
        var app = new SqlConnectionStringBuilder(appConnectionString);
        var database = admin.InitialCatalog;
        if (string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException("The admin connection string must name the database (Database=ZayPOS).");
        if (!string.Equals(app.InitialCatalog, database, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"The app connection string points at '{app.InitialCatalog}', the admin one at '{database}'.");
        ValidateAppLogin(app.UserID, app.Password);

        await WaitForServerAsync(admin, log, ct);

        await using (var db = CreateContext(adminConnectionString))
        {
            var pending = (await db.Database.GetPendingMigrationsAsync(ct)).ToList();
            if (pending.Count == 0)
                log.LogInformation("Database {Database}: no pending migrations", database);
            else
                log.LogInformation("Database {Database}: applying {Count} migration(s): {Migrations}", database, pending.Count, string.Join(", ", pending));
            await db.Database.MigrateAsync(ct);
            log.LogInformation("Database {Database}: migrations applied", database);
        }

        // Backups are nightly full backups (deploy/backup.sh), no log backups: in FULL recovery the
        // transaction log would grow until the disk is full. SIMPLE keeps it bounded.
        await ExecAsync(admin.ConnectionString, """
            IF (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) <> 'SIMPLE'
            BEGIN
                DECLARE @sql nvarchar(max) = N'ALTER DATABASE ' + QUOTENAME(DB_NAME()) + N' SET RECOVERY SIMPLE';
                EXEC (@sql);
            END
            """, ct);

        await EnsureAppLoginAsync(admin, app.UserID, app.Password, ct);
        log.LogInformation("Database {Database}: login {Login} has db_datareader + db_datawriter", database, app.UserID);
    }

    /// <summary>Migrations the code has and the database does not. Retries while SQL Server is still starting.</summary>
    public static async Task<IReadOnlyList<string>> PendingMigrationsAsync(ZayPosDbContext db, ILogger log, TimeSpan wait, CancellationToken ct = default)
    {
        var deadline = DateTime.UtcNow + wait;
        while (true)
        {
            try
            {
                return (await db.Database.GetPendingMigrationsAsync(ct)).ToList();
            }
            catch (SqlException e) when (DateTime.UtcNow < deadline && IsTransient(e))
            {
                log.LogWarning("Database not reachable yet (SQL error {Number}); retrying", e.Number);
                await Task.Delay(TimeSpan.FromSeconds(2), ct);
            }
        }
    }

    internal static void ValidateAppLogin(string login, string password)
    {
        if (!LoginName().IsMatch(login))
            throw new InvalidOperationException($"App login '{login}' must be 1-64 letters, digits or _ and start with a letter.");
        if (string.Equals(login, "sa", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("The API must not connect as sa: give it its own login (DB_APP_PASSWORD in deploy/.env).");
        if (password.Length is < 12 or > 128)
            throw new InvalidOperationException("The app login password must be 12-128 characters.");
    }

    private static async Task WaitForServerAsync(SqlConnectionStringBuilder admin, ILogger log, CancellationToken ct)
    {
        var master = new SqlConnectionStringBuilder(admin.ConnectionString) { InitialCatalog = "master" }.ConnectionString;
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(90);
        while (true)
        {
            try
            {
                await using var conn = new SqlConnection(master);
                await conn.OpenAsync(ct);
                return;
            }
            catch (SqlException e) when (DateTime.UtcNow < deadline && IsTransient(e))
            {
                log.LogInformation("Waiting for SQL Server (error {Number})", e.Number);
                await Task.Delay(TimeSpan.FromSeconds(3), ct);
            }
        }
    }

    // 18456 = login failed: also what SQL Server answers while it is still recovering at boot.
    private static bool IsTransient(SqlException e) => e.Number is 0 or -2 or 53 or 4060 or 18456 or 40613 or 233 or 10054;

    private static async Task EnsureAppLoginAsync(SqlConnectionStringBuilder admin, string login, string password, CancellationToken ct)
    {
        // DDL cannot take parameters: build it in T-SQL with QUOTENAME so neither value can break out.
        var master = new SqlConnectionStringBuilder(admin.ConnectionString) { InitialCatalog = "master" }.ConnectionString;
        await ExecAsync(master, """
            DECLARE @sql nvarchar(max) =
                CASE WHEN SUSER_ID(@login) IS NULL
                     THEN N'CREATE LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@password, '''')
                          + N', CHECK_POLICY = ON, DEFAULT_DATABASE = ' + QUOTENAME(@db)
                     ELSE N'ALTER LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@password, '''')
                          + N'; ALTER LOGIN ' + QUOTENAME(@login) + N' ENABLE'
                END;
            IF @sql IS NULL THROW 50000, 'Login statement could not be built (password too long?)', 1;
            EXEC (@sql);
            """, ct, ("@login", login), ("@password", password), ("@db", admin.InitialCatalog));

        await ExecAsync(admin.ConnectionString, """
            -- EXEC() takes no function calls, so every statement goes through @sql.
            DECLARE @q sysname = QUOTENAME(@login), @sql nvarchar(max);
            IF USER_ID(@login) IS NULL
            BEGIN
                SET @sql = N'CREATE USER ' + @q + N' FOR LOGIN ' + @q; EXEC (@sql);
            END
            SET @sql = N'ALTER ROLE db_datareader ADD MEMBER ' + @q; EXEC (@sql);
            SET @sql = N'ALTER ROLE db_datawriter ADD MEMBER ' + @q; EXEC (@sql);
            -- Least privilege: if someone widened it by hand, take it back.
            IF IS_ROLEMEMBER('db_owner', @login) = 1
            BEGIN
                SET @sql = N'ALTER ROLE db_owner DROP MEMBER ' + @q; EXEC (@sql);
            END
            IF IS_ROLEMEMBER('db_ddladmin', @login) = 1
            BEGIN
                SET @sql = N'ALTER ROLE db_ddladmin DROP MEMBER ' + @q; EXEC (@sql);
            END
            """, ct, ("@login", login));
    }

    private static async Task ExecAsync(string connectionString, string sql, CancellationToken ct, params (string Name, string Value)[] args)
    {
        await using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        foreach (var (name, value) in args)
            cmd.Parameters.Add(new SqlParameter(name, System.Data.SqlDbType.NVarChar, 256) { Value = value });
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static ZayPosDbContext CreateContext(string connectionString) =>
        new(new DbContextOptionsBuilder<ZayPosDbContext>()
                .UseSqlServer(connectionString, sql => sql.MigrationsHistoryTable("__EFMigrationsHistory", "dbo"))
                .Options,
            new NoTenant());

    private sealed class NoTenant : ICurrentTenant
    {
        public Guid? TenantId => null;
    }

    [GeneratedRegex("^[A-Za-z][A-Za-z0-9_]{0,63}$")]
    private static partial Regex LoginName();
}
