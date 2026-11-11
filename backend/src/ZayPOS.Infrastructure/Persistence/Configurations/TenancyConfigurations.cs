using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Tenancy;
using ZayPOS.Infrastructure.Persistence.Conventions;

namespace ZayPOS.Infrastructure.Persistence.Configurations;

internal sealed class TenantConfiguration : IEntityTypeConfiguration<Tenant>
{
    public void Configure(EntityTypeBuilder<Tenant> b)
    {
        b.ToTable("Tenants", t => t.HasCheckConstraint("CK_Tenants_Plan", "[Plan] IN ('free','pro')"));
        b.HasKey(x => x.Id).HasName("PK_Tenants").IsClustered();

        b.Property(x => x.Name).Nvarchar(120);
        b.Property(x => x.TemplateId).Varchar(20);
        b.Property(x => x.Township).Nvarchar(80);
        b.Property(x => x.Phone).Varchar(20);
        b.Property(x => x.Plan).CamelString(20).HasDefaultValue(TenantPlan.Free, "DF_Tenants_Plan");
        b.Property(x => x.Version).IsRowVersion();
    }
}

internal sealed class TenantFeatureConfiguration : IEntityTypeConfiguration<TenantFeature>
{
    public void Configure(EntityTypeBuilder<TenantFeature> b)
    {
        b.ToTable("TenantFeatures");
        b.HasKey(x => new { x.TenantId, x.FeatureKey }).HasName("PK_TenantFeatures").IsClustered();

        b.Property(x => x.FeatureKey).Varchar(40);
        b.Property(x => x.Version).IsRowVersion();

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_TenantFeatures_Tenant");
        b.HasIndex(x => new { x.TenantId, x.Version }).HasDatabaseName("IX_TenantFeatures_Pull");
    }
}

internal sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> b)
    {
        b.ToTable("Users", t => t.HasCheckConstraint("CK_Users_Role", "Role IN ('owner','staff')"));
        b.HasKey(x => x.Id).HasName("PK_Users").IsClustered(false);
        b.HasIndex(x => new { x.TenantId, x.CreatedAt }).HasDatabaseName("CX_Users").IsClustered();

        b.Property(x => x.Phone).Varchar(20);
        b.Property(x => x.Name).Nvarchar(80);
        b.Property(x => x.Role).CamelString(10);
        b.Property(x => x.PinHash).Varchar(200);
        b.Property(x => x.FailedPinCount).HasDefaultValue(0, "DF_Users_Failed");
        b.Property(x => x.Version).IsRowVersion();

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_Users_Tenant");
        b.HasIndex(x => x.Phone).HasDatabaseName("UX_Users_Phone").IsUnique().HasFilter("[DeletedAt] IS NULL");
    }
}

internal sealed class DeviceConfiguration : IEntityTypeConfiguration<Device>
{
    public void Configure(EntityTypeBuilder<Device> b)
    {
        b.SyncedTable("Devices");

        b.Property(x => x.Code).Varchar(3);
        b.Property(x => x.Name).Nvarchar(60);
        b.Property(x => x.LastSeq).HasDefaultValue(0, "DF_Devices_Seq");

        b.HasOne<Tenant>().WithMany().HasForeignKey(x => x.TenantId).HasConstraintName("FK_Devices_Tenant");
        b.HasIndex(x => new { x.TenantId, x.Code }).HasDatabaseName("UX_Devices_Code").IsUnique();
    }
}

internal sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> b)
    {
        b.ToTable("RefreshTokens");
        b.HasKey(x => x.Id).HasName("PK_RefreshTokens");

        b.Property(x => x.TokenHash).HasColumnType("varbinary(32)").HasMaxLength(32);

        b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).HasConstraintName("FK_RefreshTokens_User");
        b.HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).HasConstraintName("FK_RefreshTokens_Device");
        b.HasIndex(x => x.TokenHash).HasDatabaseName("UX_RefreshTokens_Hash").IsUnique();
    }
}

internal sealed class OtpChallengeConfiguration : IEntityTypeConfiguration<OtpChallenge>
{
    public void Configure(EntityTypeBuilder<OtpChallenge> b)
    {
        b.ToTable("OtpChallenges");
        b.HasKey(x => x.Id).HasName("PK_OtpChallenges");

        b.Property(x => x.Phone).Varchar(20);
        b.Property(x => x.CodeHash).HasColumnType("varbinary(32)").HasMaxLength(32);
        b.Property(x => x.Purpose).CamelString(10);
        b.Property(x => x.Attempts).HasDefaultValue(0, "DF_Otp_Attempts");

        b.HasIndex(x => new { x.Phone, x.CreatedAt }).HasDatabaseName("IX_Otp_Phone").IsDescending(false, true);
    }
}
