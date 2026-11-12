using System.Text.RegularExpressions;
using FluentAssertions;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Domain.Tests;

public class ShopTemplateTests
{
    /// <summary>Copied by hand from mobile/lib/core/features/shop_template.dart (ShopTemplate.all).</summary>
    public static TheoryData<string, string[]> Expected => new()
    {
        { "grocery", ["quickSale", "stock", "presetCatalog"] },
        { "pharmacy", ["quickSale", "stock", "presetCatalog", "expiryBatch"] },
        { "phone", ["quickSale", "stock", "presetCatalog", "serialWarranty"] },
        { "fashion", ["quickSale", "stock", "variants"] },
        { "hardware", ["quickSale", "stock", "presetCatalog", "decimalQty", "quotation"] },
        { "service", ["quickSale", "serviceItems"] },
        { "restaurant", [] },
        { "other", [] },
    };

    [Theory]
    [MemberData(nameof(Expected))]
    public void Template_seeds_exactly_these_flags(string templateId, string[] enabled)
    {
        var features = ShopTemplates.FeaturesFor(templateId);

        features.Keys.Should().BeEquivalentTo(FeatureKeys.All, "every flag gets a row, on or off");
        features.Where(f => f.Value).Select(f => f.Key).Should().BeEquivalentTo(enabled);
    }

    [Fact]
    public void Template_ids_are_exactly_the_dart_ones() =>
        ShopTemplates.Ids.Should().BeEquivalentTo(Expected.Select(row => (string)row[0]));

    [Fact]
    public void Feature_keys_match_dart_TenantFeatures_fields()
    {
        var dart = File.ReadAllText(MobileFile("lib/core/features/tenant_features.dart"));
        var fields = Regex.Matches(dart, @"final bool (\w+);").Select(m => m.Groups[1].Value);
        FeatureKeys.All.Should().Equal(fields);
    }

    /// <summary>Catches drift: parses the Dart source itself, so a change there fails here.</summary>
    [Fact]
    public void Mapping_equals_shop_template_dart()
    {
        var dart = File.ReadAllText(MobileFile("lib/core/features/shop_template.dart"));
        var parsed = Regex.Matches(dart,
                @"id:\s*'(?<id>\w+)'.*?features:\s*TenantFeatures\((?<args>[^)]*)\)",
                RegexOptions.Singleline)
            .ToDictionary(
                m => m.Groups["id"].Value,
                m => Regex.Matches(m.Groups["args"].Value, @"(\w+):\s*true").Select(f => f.Groups[1].Value).ToArray());

        parsed.Keys.Should().BeEquivalentTo(ShopTemplates.Ids);
        foreach (var (id, enabled) in parsed)
            ShopTemplates.FeaturesFor(id).Where(f => f.Value).Select(f => f.Key)
                .Should().BeEquivalentTo(enabled, $"template '{id}' must match shop_template.dart");
    }

    private static string MobileFile(string relative)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var path = Path.Combine(dir.FullName, "mobile", relative);
            if (File.Exists(path)) return path;
        }
        throw new FileNotFoundException($"mobile/{relative} not found above the test output folder.");
    }
}
