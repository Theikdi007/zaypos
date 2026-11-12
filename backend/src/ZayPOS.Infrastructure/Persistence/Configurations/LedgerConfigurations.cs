using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence.Conventions;

namespace ZayPOS.Infrastructure.Persistence.Configurations;

internal sealed class StockMovementConfiguration : IEntityTypeConfiguration<StockMovement>
{
    public void Configure(EntityTypeBuilder<StockMovement> b)
    {
        b.SyncedTable("StockMovements");
        b.ToTable(t => t.HasCheckConstraint("CK_StockMovements_Type",
            "Type IN ('sale','restock','adjustment','voidReturn')"));

        b.Property(x => x.Type).CamelString(12);
        b.Property(x => x.Note).Nvarchar(200).HasDefaultValue("", "DF_Stock_Note");

        b.HasOne<Product>().WithMany().HasForeignKey(x => x.ProductId).HasConstraintName("FK_StockMovements_Product");
        b.HasOne<ProductVariant>().WithMany().HasForeignKey(x => x.VariantId).HasConstraintName("FK_StockMovements_Variant");
        b.HasOne<ProductBatch>().WithMany().HasForeignKey(x => x.BatchId).HasConstraintName("FK_StockMovements_Batch");
        b.HasIndex(x => new { x.TenantId, x.ProductId }).HasDatabaseName("IX_StockMovements_Product")
            .IncludeProperties(x => new { x.QtyMilli, x.VariantId, x.BatchId, x.DeletedAt });
    }
}

internal sealed class CustomerConfiguration : IEntityTypeConfiguration<Customer>
{
    public void Configure(EntityTypeBuilder<Customer> b)
    {
        b.SyncedTable("Customers");

        b.Property(x => x.Name).Nvarchar(100);
        b.Property(x => x.Phone).Varchar(20).HasDefaultValue("", "DF_Customers_Phone");
        b.Property(x => x.Address).Nvarchar(200);
        b.Property(x => x.Note).Nvarchar(300);

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_Customers_Tenant");
    }
}

internal sealed class DebtEntryConfiguration : IEntityTypeConfiguration<DebtEntry>
{
    public void Configure(EntityTypeBuilder<DebtEntry> b)
    {
        b.SyncedTable("DebtEntries");
        b.ToTable(t =>
        {
            t.HasCheckConstraint("CK_DebtEntries_Type", "Type IN ('creditSale','payment','adjustment')");
            t.HasCheckConstraint("CK_DebtEntries_Sign", "Type = 'adjustment' OR Amount > 0");
        });
        b.Ignore(x => x.Effect);

        b.Property(x => x.Type).CamelString(12);
        b.Property(x => x.SaleNo).Varchar(12);
        b.Property(x => x.Method).CamelString(10);
        b.Property(x => x.Note).Nvarchar(200);

        b.HasOne<Customer>().WithMany().HasForeignKey(x => x.CustomerId).HasConstraintName("FK_DebtEntries_Customer");
        b.HasIndex(x => new { x.TenantId, x.CustomerId }).HasDatabaseName("IX_DebtEntries_Customer")
            .IncludeProperties(x => new { x.Type, x.Amount, x.DeletedAt, x.CreatedAt });
    }
}
