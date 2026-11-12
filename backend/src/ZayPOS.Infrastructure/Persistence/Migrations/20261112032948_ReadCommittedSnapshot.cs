using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZayPOS.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// Read Committed Snapshot Isolation: readers (sync pull, reports) see the last committed
    /// version instead of blocking on an open push transaction, and pushes are not blocked by
    /// readers. Pull stays correct because it never reads at/after MIN_ACTIVE_ROWVERSION().
    /// ALTER DATABASE can't run inside a transaction; ROLLBACK IMMEDIATE ends other sessions'
    /// open transactions so the switch doesn't wait forever (run during a deploy window).
    /// Azure SQL Database already has it on; the statement is then a no-op.
    /// </summary>
    public partial class ReadCommittedSnapshot : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                "ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;",
                suppressTransaction: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                "ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;",
                suppressTransaction: true);
        }
    }
}
