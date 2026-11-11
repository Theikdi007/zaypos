using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZayPOS.Domain.Billing;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence.Conventions;

namespace ZayPOS.Infrastructure.Persistence.Configurations;

internal sealed class ProcessedUnitConfiguration : IEntityTypeConfiguration<ProcessedUnit>
{
    public void Configure(EntityTypeBuilder<ProcessedUnit> b)
    {
        b.ToTable("ProcessedUnits");
        b.HasKey(x => new { x.TenantId, x.UnitId }).HasName("PK_ProcessedUnits");

        b.Property(x => x.Outcome).CamelString(10);
    }
}

internal sealed class SyncIssueConfiguration : IEntityTypeConfiguration<SyncIssue>
{
    public void Configure(EntityTypeBuilder<SyncIssue> b)
    {
        b.SyncedTable("SyncIssues");

        b.Property(x => x.Kind).CamelString(30);
        b.Property(x => x.EntityTable).Varchar(40);
        b.Property(x => x.Detail).Nvarchar(400);

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_SyncIssues_Tenant");
    }
}

internal sealed class SubscriptionPaymentConfiguration : IEntityTypeConfiguration<SubscriptionPayment>
{
    public void Configure(EntityTypeBuilder<SubscriptionPayment> b)
    {
        b.ToTable("SubscriptionPayments", t => t.HasCheckConstraint("CK_SubscriptionPayments_Status",
            "Status IN ('pending','approved','rejected')"));
        b.HasKey(x => x.Id).HasName("PK_SubscriptionPayments").IsClustered(false);
        b.HasIndex(x => new { x.TenantId, x.CreatedAt }).HasDatabaseName("CX_SubscriptionPayments").IsClustered();

        b.Property(x => x.Method).CamelString(10);
        b.Property(x => x.ScreenshotKey).Varchar(200);
        b.Property(x => x.Status).CamelString(10);
        b.Property(x => x.ReviewedBy).Nvarchar(80);
        b.Property(x => x.Version).IsRowVersion();

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_SubscriptionPayments_Tenant");
    }
}
