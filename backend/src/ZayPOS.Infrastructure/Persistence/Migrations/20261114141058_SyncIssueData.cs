using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZayPOS.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class SyncIssueData : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Data",
                schema: "dbo",
                table: "SyncIssues",
                type: "nvarchar(2000)",
                maxLength: 2000,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Data",
                schema: "dbo",
                table: "SyncIssues");
        }
    }
}
