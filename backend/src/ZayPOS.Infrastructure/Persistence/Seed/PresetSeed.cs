using ZayPOS.Domain.Catalog;

namespace ZayPOS.Infrastructure.Persistence.Seed;

/// <summary>
/// Sample starter catalog for the grocery template (categories and units from
/// <c>ShopTemplate.all</c> in mobile/lib/core/features/shop_template.dart). Prices are rough
/// suggestions in kyats; barcodes are left empty on purpose (never invent real-looking EANs).
/// Ids and UpdatedAt are fixed so the seed is stable across migrations; change a row = new migration.
/// </summary>
internal static class PresetSeed
{
    private static readonly DateTime Seeded = new(2026, 11, 12, 0, 0, 0, DateTimeKind.Utc);

    private const string Food = "စားသောက်ကုန်";
    private const string Drinks = "အချိုရည်";
    private const string Household = "အိမ်သုံး";
    private const string Snacks = "မုန့်";

    private static readonly (string Name, string Category, string Unit, long Price)[] Grocery =
    [
        ("ဆန် (ပေါ်ဆန်း)", Food, "ပြည်", 8_500),
        ("ပဲဆီ", Food, "ပိဿာ", 16_000),
        ("သကြား", Food, "ပိဿာ", 6_500),
        ("ဆား", Food, "ထုပ်", 500),
        ("ကြက်ဥ", Food, "ခု", 300),
        ("ကြက်သွန်နီ", Food, "ပိဿာ", 5_000),
        ("ကြက်သွန်ဖြူ", Food, "ပိဿာ", 8_000),
        ("ငံပြာရည်", Food, "ဗူး", 2_500),
        ("အချိုမှုန့်", Food, "ထုပ်", 1_500),
        ("အသင့်စား ခေါက်ဆွဲ", Food, "ထုပ်", 600),
        ("လက်ဖက်ခြောက်", Food, "ထုပ်", 1_500),
        ("ရေသန့် 1L", Drinks, "ဗူး", 600),
        ("ကော်ဖီမစ် 3 in 1", Drinks, "ထုပ်", 300),
        ("အချိုရည် ဗူး", Drinks, "ဗူး", 1_200),
        ("ဆပ်ပြာခဲ", Household, "ခု", 1_200),
        ("ဆပ်ပြာမှုန့်", Household, "ထုပ်", 2_000),
        ("သွားတိုက်ဆေး", Household, "ခု", 2_500),
        ("မီးခြစ်", Household, "ခု", 200),
        ("ဖယောင်းတိုင်", Household, "ထုပ်", 1_000),
        ("ဘီစကွတ်", Snacks, "ထုပ်", 1_000),
    ];

    public static IEnumerable<PresetProduct> All() =>
        Grocery.Select((p, i) => new PresetProduct
        {
            // 019a7000-0000-7000-8000-0000000001NN: v7-shaped, readable, never collides with app ids.
            Id = Guid.Parse($"019a7000-0000-7000-8000-{0x100 + i + 1:x12}"),
            TemplateId = "grocery",
            Name = p.Name, Category = p.Category, Unit = p.Unit, Barcode = null,
            SuggestedPrice = p.Price, SortOrder = (i + 1) * 10, UpdatedAt = Seeded,
        });
}
