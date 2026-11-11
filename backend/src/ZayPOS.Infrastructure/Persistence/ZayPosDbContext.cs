using System.Reflection;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using ZayPOS.Application.Abstractions;
using ZayPOS.Domain.Billing;
using ZayPOS.Domain.Catalog;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Customers;
using ZayPOS.Domain.Inventory;
using ZayPOS.Domain.Sales;
using ZayPOS.Domain.Sync;
using ZayPOS.Domain.Tenancy;

namespace ZayPOS.Infrastructure.Persistence;

public class ZayPosDbContext(DbContextOptions<ZayPosDbContext> options, ICurrentTenant currentTenant)
    : DbContext(options)
{
    /// <summary>Read by the global query filters; EF re-evaluates it per query.</summary>
    public Guid? CurrentTenantId => currentTenant.TenantId;

    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<TenantFeature> TenantFeatures => Set<TenantFeature>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<OtpChallenge> OtpChallenges => Set<OtpChallenge>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<ProductVariant> ProductVariants => Set<ProductVariant>();
    public DbSet<ProductBatch> ProductBatches => Set<ProductBatch>();
    public DbSet<ProductSerial> ProductSerials => Set<ProductSerial>();
    public DbSet<PresetProduct> PresetProducts => Set<PresetProduct>();
    public DbSet<StockMovement> StockMovements => Set<StockMovement>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<DebtEntry> DebtEntries => Set<DebtEntry>();
    public DbSet<Sale> Sales => Set<Sale>();
    public DbSet<SaleLine> SaleLines => Set<SaleLine>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<ProcessedUnit> ProcessedUnits => Set<ProcessedUnit>();
    public DbSet<SyncIssue> SyncIssues => Set<SyncIssue>();
    public DbSet<SubscriptionPayment> SubscriptionPayments => Set<SubscriptionPayment>();

    protected override void ConfigureConventions(ModelConfigurationBuilder b)
    {
        // Every time column is datetime2(3), UTC. Values read back are marked Kind=Utc.
        b.Properties<DateTime>().HavePrecision(3).HaveConversion<UtcDateTimeConverter>();
        b.Properties<DateTime?>().HavePrecision(3).HaveConversion<UtcNullableDateTimeConverter>();

        // schema.sql declares every index explicitly; don't let EF add one per FK.
        b.Conventions.Remove<ForeignKeyIndexConvention>();
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("dbo");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ZayPosDbContext).Assembly);

        // No cascades anywhere: ledgers and sales are append-only, rows are soft-deleted.
        foreach (var fk in modelBuilder.Model.GetEntityTypes().SelectMany(e => e.GetForeignKeys()))
            fk.DeleteBehavior = DeleteBehavior.NoAction;

        ApplyTenantFilters(modelBuilder);
    }

    private void ApplyTenantFilters(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Tenant>().HasQueryFilter(t => t.Id == CurrentTenantId);

        var method = typeof(ZayPosDbContext).GetMethod(nameof(SetTenantFilter), BindingFlags.NonPublic | BindingFlags.Instance)!;
        foreach (var entity in modelBuilder.Model.GetEntityTypes())
        {
            if (typeof(ITenantOwned).IsAssignableFrom(entity.ClrType))
                method.MakeGenericMethod(entity.ClrType).Invoke(this, [modelBuilder]);
        }
    }

    private void SetTenantFilter<T>(ModelBuilder modelBuilder) where T : class, ITenantOwned =>
        modelBuilder.Entity<T>().HasQueryFilter(e => e.TenantId == CurrentTenantId);
}

internal sealed class UtcDateTimeConverter() : ValueConverter<DateTime, DateTime>(
    v => v.Kind == DateTimeKind.Utc ? v : v.ToUniversalTime(),
    v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

internal sealed class UtcNullableDateTimeConverter() : ValueConverter<DateTime?, DateTime?>(
    v => v == null ? v : v.Value.Kind == DateTimeKind.Utc ? v : v.Value.ToUniversalTime(),
    v => v == null ? v : DateTime.SpecifyKind(v.Value, DateTimeKind.Utc));
