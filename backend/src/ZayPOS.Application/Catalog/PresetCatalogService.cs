using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Application.Catalog;

public sealed record PresetItem(Guid Id, string Name, string Category, string Unit, string? Barcode, long? SuggestedPrice, int SortOrder);

public sealed record PresetCatalog(string Template, IReadOnlyList<PresetItem> Items);

/// <summary>Global starter catalog per shop template (not tenant data). HTTP caching lives in the endpoint.</summary>
public sealed class PresetCatalogService(IAppDb db)
{
    public async Task<PresetCatalog> GetAsync(string template, CancellationToken ct)
    {
        if (!ShopTemplates.Exists(template))
            throw new ApiException(400, "validation", $"Unknown template '{template}'. Known: {string.Join(", ", ShopTemplates.Ids)}.");

        var items = await db.Set<PresetProduct>().AsNoTracking()
            .Where(p => p.TemplateId == template)
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Id)
            .Select(p => new PresetItem(p.Id, p.Name, p.Category, p.Unit, p.Barcode, p.SuggestedPrice, p.SortOrder))
            .ToListAsync(ct);
        return new PresetCatalog(template, items);
    }

    /// <summary>The caller's own template, for <c>GET /catalog/presets</c> without <c>?template</c>.</summary>
    public Task<string> TenantTemplateAsync(CancellationToken ct) =>
        db.Set<Tenant>().AsNoTracking().Select(t => t.TemplateId).FirstAsync(ct);
}
