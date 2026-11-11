using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Api.Tests;

[Collection(SqlServerCollection.Name)]
public class SchemaTests(SqlServerFixture sql)
{
    [Fact]
    public async Task Model_has_no_changes_missing_from_migrations()
    {
        await using var db = sql.CreateContext(null);
        db.Database.HasPendingModelChanges().Should().BeFalse();
        (await db.Database.GetPendingMigrationsAsync()).Should().BeEmpty();
    }

    [Fact]
    public async Task Tenant_filter_hides_other_tenants_rows()
    {
        var (a, pa) = await SeedTenantWithProduct("A");
        var (b, pb) = await SeedTenantWithProduct("B");

        await using (var dbA = sql.CreateContext(a))
        {
            var ids = await dbA.Products.Select(p => p.Id).ToListAsync();
            ids.Should().Contain(pa).And.NotContain(pb);
            (await dbA.Tenants.Select(t => t.Id).ToListAsync()).Should().Equal(a);
        }

        await using (var anonymous = sql.CreateContext(null))
        {
            (await anonymous.Products.AnyAsync(p => p.Id == pa || p.Id == pb)).Should().BeFalse();
            (await anonymous.Products.IgnoreQueryFilters().CountAsync(p => p.Id == pa || p.Id == pb)).Should().Be(2);
        }
    }

    [Fact]
    public async Task Enums_are_stored_as_dart_camelCase_names_and_times_read_back_as_utc()
    {
        var (tenant, product) = await SeedTenantWithProduct("C");
        var movementId = Guid.CreateVersion7();
        var now = DateTime.UtcNow;

        await using (var db = sql.CreateContext(tenant))
        {
            db.StockMovements.Add(new StockMovement
            {
                Id = movementId, TenantId = tenant, ProductId = product,
                Type = StockMovementType.VoidReturn, QtyMilli = 2500, CreatedAt = now, UpdatedAt = now,
            });
            await db.SaveChangesAsync();
        }

        await using (var db = sql.CreateContext(tenant))
        {
            var raw = await db.Database
                .SqlQuery<string>($"SELECT Type AS Value FROM dbo.StockMovements WHERE Id = {movementId}")
                .SingleAsync();
            raw.Should().Be("voidReturn");

            var m = await db.StockMovements.SingleAsync(x => x.Id == movementId);
            m.Type.Should().Be(StockMovementType.VoidReturn);
            m.Note.Should().BeEmpty();
            m.CreatedAt.Kind.Should().Be(DateTimeKind.Utc);
            m.Version.Should().HaveCount(8);
        }
    }

    private async Task<(Guid Tenant, Guid Product)> SeedTenantWithProduct(string name)
    {
        var tenantId = Guid.CreateVersion7();
        var productId = Guid.CreateVersion7();
        var now = DateTime.UtcNow;

        await using var db = sql.CreateContext(tenantId);
        db.Tenants.Add(new Tenant
        {
            Id = tenantId, Name = name, TemplateId = "grocery", Phone = "+959000000000",
            CreatedAt = now, UpdatedAt = now,
        });
        db.Products.Add(new Product
        {
            Id = productId, TenantId = tenantId, Name = "ဆန်", Category = "ဆန်", Unit = "ပြည်",
            Cost = 3000, Price = 3500, LowAlertMilli = 5000, Tint = unchecked((int)0xFFE0F2F1), Initial = "ဆ",
            CreatedAt = now, UpdatedAt = now,
        });
        await db.SaveChangesAsync();

        var plan = await db.Database
            .SqlQuery<string>($"SELECT [Plan] AS Value FROM dbo.Tenants WHERE Id = {tenantId}").SingleAsync();
        plan.Should().Be("free");
        return (tenantId, productId);
    }
}
