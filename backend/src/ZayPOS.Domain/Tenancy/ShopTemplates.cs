namespace ZayPOS.Domain.Tenancy;

/// <summary>Dart <c>TenantFeatures</c> field names = <c>TenantFeatures.FeatureKey</c> values.</summary>
public static class FeatureKeys
{
    public const string QuickSale = "quickSale";
    public const string Stock = "stock";
    public const string PresetCatalog = "presetCatalog";
    public const string ExpiryBatch = "expiryBatch";
    public const string SerialWarranty = "serialWarranty";
    public const string Variants = "variants";
    public const string DecimalQty = "decimalQty";
    public const string Quotation = "quotation";
    public const string ServiceItems = "serviceItems";

    /// <summary>All flags, in Dart declaration order.</summary>
    public static readonly IReadOnlyList<string> All =
    [
        QuickSale, Stock, PresetCatalog, ExpiryBatch, SerialWarranty, Variants, DecimalQty, Quotation, ServiceItems,
    ];
}

/// <summary>
/// Template → initial feature flags. Must equal <c>ShopTemplate.all</c> in
/// mobile/lib/core/features/shop_template.dart (guarded by a test that parses it).
/// A template only seeds flags; nothing branches on the template id.
/// </summary>
public static class ShopTemplates
{
    private static readonly Dictionary<string, string[]> Enabled = new(StringComparer.Ordinal)
    {
        ["grocery"] = [FeatureKeys.QuickSale, FeatureKeys.Stock, FeatureKeys.PresetCatalog],
        ["pharmacy"] = [FeatureKeys.QuickSale, FeatureKeys.Stock, FeatureKeys.PresetCatalog, FeatureKeys.ExpiryBatch],
        ["phone"] = [FeatureKeys.QuickSale, FeatureKeys.Stock, FeatureKeys.PresetCatalog, FeatureKeys.SerialWarranty],
        ["fashion"] = [FeatureKeys.QuickSale, FeatureKeys.Stock, FeatureKeys.Variants],
        ["hardware"] = [FeatureKeys.QuickSale, FeatureKeys.Stock, FeatureKeys.PresetCatalog, FeatureKeys.DecimalQty, FeatureKeys.Quotation],
        ["service"] = [FeatureKeys.QuickSale, FeatureKeys.ServiceItems],
        ["restaurant"] = [],
        ["other"] = [],
    };

    public static IReadOnlyCollection<string> Ids => Enabled.Keys;

    public static bool Exists(string templateId) => Enabled.ContainsKey(templateId);

    /// <summary>Every feature key with its initial value for <paramref name="templateId"/>.</summary>
    public static IReadOnlyDictionary<string, bool> FeaturesFor(string templateId)
    {
        if (!Enabled.TryGetValue(templateId, out var on))
            throw new ArgumentException($"Unknown shop template '{templateId}'.", nameof(templateId));
        return FeatureKeys.All.ToDictionary(k => k, k => on.Contains(k));
    }
}
