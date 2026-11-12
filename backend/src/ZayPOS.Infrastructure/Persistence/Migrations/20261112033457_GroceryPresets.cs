using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace ZayPOS.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class GroceryPresets : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.InsertData(
                schema: "dbo",
                table: "PresetProducts",
                columns: new[] { "Id", "Barcode", "Category", "Name", "SortOrder", "SuggestedPrice", "TemplateId", "Unit", "UpdatedAt" },
                values: new object[,]
                {
                    { new Guid("019a7000-0000-7000-8000-000000000101"), null, "စားသောက်ကုန်", "ဆန် (ပေါ်ဆန်း)", 10, 8500L, "grocery", "ပြည်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000102"), null, "စားသောက်ကုန်", "ပဲဆီ", 20, 16000L, "grocery", "ပိဿာ", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000103"), null, "စားသောက်ကုန်", "သကြား", 30, 6500L, "grocery", "ပိဿာ", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000104"), null, "စားသောက်ကုန်", "ဆား", 40, 500L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000105"), null, "စားသောက်ကုန်", "ကြက်ဥ", 50, 300L, "grocery", "ခု", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000106"), null, "စားသောက်ကုန်", "ကြက်သွန်နီ", 60, 5000L, "grocery", "ပိဿာ", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000107"), null, "စားသောက်ကုန်", "ကြက်သွန်ဖြူ", 70, 8000L, "grocery", "ပိဿာ", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000108"), null, "စားသောက်ကုန်", "ငံပြာရည်", 80, 2500L, "grocery", "ဗူး", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000109"), null, "စားသောက်ကုန်", "အချိုမှုန့်", 90, 1500L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010a"), null, "စားသောက်ကုန်", "အသင့်စား ခေါက်ဆွဲ", 100, 600L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010b"), null, "စားသောက်ကုန်", "လက်ဖက်ခြောက်", 110, 1500L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010c"), null, "အချိုရည်", "ရေသန့် 1L", 120, 600L, "grocery", "ဗူး", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010d"), null, "အချိုရည်", "ကော်ဖီမစ် 3 in 1", 130, 300L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010e"), null, "အချိုရည်", "အချိုရည် ဗူး", 140, 1200L, "grocery", "ဗူး", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-00000000010f"), null, "အိမ်သုံး", "ဆပ်ပြာခဲ", 150, 1200L, "grocery", "ခု", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000110"), null, "အိမ်သုံး", "ဆပ်ပြာမှုန့်", 160, 2000L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000111"), null, "အိမ်သုံး", "သွားတိုက်ဆေး", 170, 2500L, "grocery", "ခု", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000112"), null, "အိမ်သုံး", "မီးခြစ်", 180, 200L, "grocery", "ခု", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000113"), null, "အိမ်သုံး", "ဖယောင်းတိုင်", 190, 1000L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) },
                    { new Guid("019a7000-0000-7000-8000-000000000114"), null, "မုန့်", "ဘီစကွတ်", 200, 1000L, "grocery", "ထုပ်", new DateTime(2026, 11, 12, 0, 0, 0, 0, DateTimeKind.Utc) }
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000101"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000102"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000103"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000104"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000105"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000106"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000107"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000108"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000109"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010a"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010b"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010c"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010d"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010e"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-00000000010f"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000110"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000111"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000112"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000113"));

            migrationBuilder.DeleteData(
                schema: "dbo",
                table: "PresetProducts",
                keyColumn: "Id",
                keyValue: new Guid("019a7000-0000-7000-8000-000000000114"));
        }
    }
}
