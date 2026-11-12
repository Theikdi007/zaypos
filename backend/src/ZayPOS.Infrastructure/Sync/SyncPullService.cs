using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence;

namespace ZayPOS.Infrastructure.Sync;

/// <summary>
/// GET /sync/pull (README §3.2): every synced table, Version in (cursor, MIN_ACTIVE_ROWVERSION()),
/// merged by Version, first <c>limit</c> rows. Tenant isolation is the global query filter.
/// </summary>
internal sealed class SyncPullService(ZayPosDbContext db) : ISyncPull
{
    public async Task<PullResponse> PullAsync(byte[] cursor, int limit, CancellationToken ct)
    {
        limit = Math.Clamp(limit, 1, SyncLimits.PullMaxLimit);

        // A transaction that is still open may hold a LOWER rowversion than rows already committed.
        // Never read at or past the oldest active one, or the cursor could jump over it forever.
        var upper = await db.Database
            .SqlQueryRaw<byte[]>("SELECT CAST(MIN_ACTIVE_ROWVERSION() AS binary(8)) AS [Value]")
            .SingleAsync(ct);

        var found = new List<(byte[] Version, Action<PullChanges> Add)>();
        async Task Read<T>(string table, Func<T, Action<PullChanges>> add) where T : class, IVersioned
        {
            // Table names come from the fixed list below, never from input; values are parameters.
#pragma warning disable EF1002
            var page = await db.Set<T>()
                .FromSqlRaw($"SELECT * FROM [dbo].[{table}] WHERE [Version] > @cursor AND [Version] < @upper",
                    Binary("@cursor", cursor), Binary("@upper", upper))
#pragma warning restore EF1002
                .AsNoTracking()
                .OrderBy(x => x.Version)
                .Take(limit + 1)
                .ToListAsync(ct);
            found.AddRange(page.Select(row => (row.Version, add(row))));
        }

        await Read<Tenant>("Tenants", r => c => c.Tenants.Add(r.ToRow()));
        await Read<TenantFeature>("TenantFeatures", r => c => c.TenantFeatures.Add(r.ToRow()));
        await Read<Device>("Devices", r => c => c.Devices.Add(r.ToRow()));
        await Read<Product>("Products", r => c => c.Products.Add(r.ToRow()));
        await Read<ProductVariant>("ProductVariants", r => c => c.ProductVariants.Add(r.ToRow()));
        await Read<ProductBatch>("ProductBatches", r => c => c.ProductBatches.Add(r.ToRow()));
        await Read<ProductSerial>("ProductSerials", r => c => c.ProductSerials.Add(r.ToRow()));
        await Read<Customer>("Customers", r => c => c.Customers.Add(r.ToRow()));
        await Read<Sale>("Sales", r => c => c.Sales.Add(r.ToRow()));
        await Read<SaleLine>("SaleLines", r => c => c.SaleLines.Add(r.ToRow()));
        await Read<Payment>("Payments", r => c => c.Payments.Add(r.ToRow()));
        await Read<StockMovement>("StockMovements", r => c => c.StockMovements.Add(r.ToRow()));
        await Read<DebtEntry>("DebtEntries", r => c => c.DebtEntries.Add(r.ToRow()));
        await Read<SyncIssue>("SyncIssues", r => c => c.SyncIssues.Add(r.ToRow()));

        found.Sort((a, b) => SyncCursor.Compare(a.Version, b.Version));
        var page = found.Take(limit).ToList();
        var changes = new PullChanges();
        foreach (var (_, add) in page) add(changes);

        var next = page.Count > 0 ? page[^1].Version : cursor;
        return new PullResponse(changes, SyncCursor.Format(next), HasMore: found.Count > limit);
    }

    private static SqlParameter Binary(string name, byte[] value) =>
        new(name, SqlDbType.Binary, 8) { Value = value };
}
