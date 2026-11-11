using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence.Conventions;

namespace ZayPOS.Infrastructure.Persistence.Configurations;

internal sealed class ProductConfiguration : IEntityTypeConfiguration<Product>
{
    public void Configure(EntityTypeBuilder<Product> b)
    {
        b.SyncedTable("Products");
        b.ToTable(t => t.HasCheckConstraint("CK_Products_Money",
            "Cost >= 0 AND Price >= 0 AND (WholesalePrice IS NULL OR WholesalePrice >= 0)"));

        b.Property(x => x.Name).Nvarchar(150);
        b.Property(x => x.Category).Nvarchar(60);
        b.Property(x => x.Unit).Nvarchar(20);
        b.Property(x => x.Barcode).Varchar(64);
        b.Property(x => x.Initial).Nvarchar(4);

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_Products_Tenant");
        // Barcodes are NOT unique: duplicates become a SyncIssue, never rejected.
        b.HasIndex(x => new { x.TenantId, x.Barcode }).HasDatabaseName("IX_Products_Barcode")
            .HasFilter("[Barcode] IS NOT NULL AND [DeletedAt] IS NULL");
    }
}

internal sealed class ProductVariantConfiguration : IEntityTypeConfiguration<ProductVariant>
{
    public void Configure(EntityTypeBuilder<ProductVariant> b)
    {
        b.SyncedTable("ProductVariants");

        b.Property(x => x.Size).Nvarchar(20);
        b.Property(x => x.Color).Nvarchar(30);

        b.HasOne<Product>().WithMany().HasForeignKey(x => x.ProductId).HasConstraintName("FK_ProductVariants_Product");
        b.HasIndex(x => x.ProductId).HasDatabaseName("IX_ProductVariants_Product");
    }
}

internal sealed class ProductBatchConfiguration : IEntityTypeConfiguration<ProductBatch>
{
    public void Configure(EntityTypeBuilder<ProductBatch> b)
    {
        b.SyncedTable("ProductBatches");

        b.Property(x => x.BatchNo).Nvarchar(40);

        b.HasOne<Product>().WithMany().HasForeignKey(x => x.ProductId).HasConstraintName("FK_ProductBatches_Product");
        b.HasIndex(x => new { x.TenantId, x.ExpiryDate }).HasDatabaseName("IX_ProductBatches_Expiry")
            .HasFilter("[DeletedAt] IS NULL");
    }
}

internal sealed class ProductSerialConfiguration : IEntityTypeConfiguration<ProductSerial>
{
    public void Configure(EntityTypeBuilder<ProductSerial> b)
    {
        b.SyncedTable("ProductSerials");
        b.ToTable(t => t.HasCheckConstraint("CK_ProductSerials_Status", "Status IN ('inStock','sold')"));

        b.Property(x => x.Serial).Varchar(40);
        b.Property(x => x.Status).CamelString(10);

        b.HasOne<Product>().WithMany().HasForeignKey(x => x.ProductId).HasConstraintName("FK_ProductSerials_Product");
        b.HasIndex(x => new { x.TenantId, x.Serial }).HasDatabaseName("IX_ProductSerials_Serial")
            .HasFilter("[DeletedAt] IS NULL");
    }
}

internal sealed class PresetProductConfiguration : IEntityTypeConfiguration<PresetProduct>
{
    public void Configure(EntityTypeBuilder<PresetProduct> b)
    {
        b.ToTable("PresetProducts");
        b.HasKey(x => x.Id).HasName("PK_PresetProducts").IsClustered(false);
        b.HasIndex(x => new { x.TemplateId, x.SortOrder }).HasDatabaseName("CX_PresetProducts").IsClustered();

        b.Property(x => x.TemplateId).Varchar(20);
        b.Property(x => x.Name).Nvarchar(150);
        b.Property(x => x.Category).Nvarchar(60);
        b.Property(x => x.Unit).Nvarchar(20);
        b.Property(x => x.Barcode).Varchar(64);
        b.Property(x => x.SortOrder).HasDefaultValue(0, "DF_Preset_Sort");
    }
}
