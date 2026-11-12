using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence.Conventions;

namespace ZayPOS.Infrastructure.Persistence.Configurations;

internal sealed class SaleConfiguration : IEntityTypeConfiguration<Sale>
{
    public void Configure(EntityTypeBuilder<Sale> b)
    {
        b.SyncedTable("Sales");
        b.ToTable(t =>
        {
            t.HasCheckConstraint("CK_Sales_Method", "Method IN ('cash','kbz','wave','debt')");
            t.HasCheckConstraint("CK_Sales_DebtCustomer", "Method <> 'debt' OR CustomerId IS NOT NULL");
        });

        b.Property(x => x.No).Varchar(12);
        b.Property(x => x.Method).CamelString(10);
        b.Property(x => x.CustomerName).Nvarchar(100);
        b.Property(x => x.ReceivedAt).HasDefaultValueSql("SYSUTCDATETIME()", "DF_Sales_Received");

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_Sales_Tenant");
        b.HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).HasConstraintName("FK_Sales_Device");
        b.HasOne<Customer>().WithMany().HasForeignKey(x => x.CustomerId).HasConstraintName("FK_Sales_Customer");
        b.HasMany(x => x.Lines).WithOne().HasForeignKey(x => x.SaleId).HasConstraintName("FK_SaleLines_Sale");
        b.HasMany(x => x.Payments).WithOne().HasForeignKey(x => x.SaleId).HasConstraintName("FK_Payments_Sale");

        b.HasIndex(x => new { x.TenantId, x.No }).HasDatabaseName("UX_Sales_No").IsUnique();
    }
}

internal sealed class SaleLineConfiguration : IEntityTypeConfiguration<SaleLine>
{
    public void Configure(EntityTypeBuilder<SaleLine> b)
    {
        b.SyncedTable("SaleLines");
        b.ToTable(t => t.HasCheckConstraint("CK_SaleLines_Qty", "QtyMilli > 0 AND Price >= 0 AND CostSnapshot >= 0"));

        b.Property(x => x.Name).Nvarchar(150);

        b.HasOne<Product>().WithMany().HasForeignKey(x => x.ProductId).HasConstraintName("FK_SaleLines_Product");
        b.HasOne<ProductSerial>().WithMany().HasForeignKey(x => x.SerialId).HasConstraintName("FK_SaleLines_Serial");
        b.HasIndex(x => x.SaleId).HasDatabaseName("IX_SaleLines_Sale");
        b.HasIndex(x => new { x.TenantId, x.ProductId }).HasDatabaseName("IX_SaleLines_Product")
            .IncludeProperties(x => new { x.QtyMilli, x.LineTotal, x.CostSnapshot });
    }
}

internal sealed class PaymentConfiguration : IEntityTypeConfiguration<Payment>
{
    public void Configure(EntityTypeBuilder<Payment> b)
    {
        b.SyncedTable("Payments");
        b.ToTable(t =>
        {
            t.HasCheckConstraint("CK_Payments_Method", "Method IN ('cash','kbz','wave')");
            t.HasCheckConstraint("CK_Payments_Amount", "Amount >= 0 AND (Received IS NULL OR Received >= Amount)");
        });

        b.Property(x => x.Method).CamelString(10);

        b.HasIndex(x => x.SaleId).HasDatabaseName("IX_Payments_Sale");
    }
}
