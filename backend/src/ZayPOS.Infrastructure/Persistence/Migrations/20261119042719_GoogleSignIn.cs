using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZayPOS.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class GoogleSignIn : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "UX_Users_Phone",
                schema: "dbo",
                table: "Users");

            migrationBuilder.AlterColumn<string>(
                name: "Phone",
                schema: "dbo",
                table: "Users",
                type: "varchar(20)",
                unicode: false,
                maxLength: 20,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "varchar(20)",
                oldUnicode: false,
                oldMaxLength: 20);

            migrationBuilder.AddColumn<string>(
                name: "GoogleEmail",
                schema: "dbo",
                table: "Users",
                type: "nvarchar(320)",
                maxLength: 320,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GoogleSubject",
                schema: "dbo",
                table: "Users",
                type: "varchar(255)",
                unicode: false,
                maxLength: 255,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "UX_Users_Google",
                schema: "dbo",
                table: "Users",
                columns: new[] { "GoogleSubject", "TenantId" },
                unique: true,
                filter: "[GoogleSubject] IS NOT NULL AND [DeletedAt] IS NULL");

            migrationBuilder.CreateIndex(
                name: "UX_Users_Phone",
                schema: "dbo",
                table: "Users",
                column: "Phone",
                unique: true,
                filter: "[Phone] IS NOT NULL AND [DeletedAt] IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "UX_Users_Google",
                schema: "dbo",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "UX_Users_Phone",
                schema: "dbo",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "GoogleEmail",
                schema: "dbo",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "GoogleSubject",
                schema: "dbo",
                table: "Users");

            migrationBuilder.AlterColumn<string>(
                name: "Phone",
                schema: "dbo",
                table: "Users",
                type: "varchar(20)",
                unicode: false,
                maxLength: 20,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "varchar(20)",
                oldUnicode: false,
                oldMaxLength: 20,
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "UX_Users_Phone",
                schema: "dbo",
                table: "Users",
                column: "Phone",
                unique: true,
                filter: "[DeletedAt] IS NULL");
        }
    }
}
