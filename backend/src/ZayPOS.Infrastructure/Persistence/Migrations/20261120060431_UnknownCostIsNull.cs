using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZayPOS.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class UnknownCostIsNull : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<long>(
                name: "CostSnapshot",
                schema: "dbo",
                table: "SaleLines",
                type: "bigint",
                nullable: true,
                oldClrType: typeof(long),
                oldType: "bigint");

            migrationBuilder.AlterColumn<long>(
                name: "Cost",
                schema: "dbo",
                table: "Products",
                type: "bigint",
                nullable: true,
                oldClrType: typeof(long),
                oldType: "bigint");

            // BUG-61: until now 0 meant "unknown" (the app had no other way to say it). Keep that meaning:
            // 0 → NULL. From here on 0 is a real zero cost. Every phone migrates its own copy the same way
            // (app schema 3), so UpdatedAt is not touched and nothing is re-synced.
            migrationBuilder.Sql("UPDATE dbo.Products SET Cost = NULL WHERE Cost = 0;");
            migrationBuilder.Sql("UPDATE dbo.SaleLines SET CostSnapshot = NULL WHERE CostSnapshot = 0;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<long>(
                name: "CostSnapshot",
                schema: "dbo",
                table: "SaleLines",
                type: "bigint",
                nullable: false,
                defaultValue: 0L,
                oldClrType: typeof(long),
                oldType: "bigint",
                oldNullable: true);

            migrationBuilder.AlterColumn<long>(
                name: "Cost",
                schema: "dbo",
                table: "Products",
                type: "bigint",
                nullable: false,
                defaultValue: 0L,
                oldClrType: typeof(long),
                oldType: "bigint",
                oldNullable: true);
        }
    }
}
