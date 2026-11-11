using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using ZayPOS.Domain.Common;

namespace ZayPOS.Infrastructure.Persistence.Conventions;

/// <summary>Small helpers so each configuration reads like its CREATE TABLE in schema.sql.</summary>
internal static class ModelBuilderExtensions
{
    /// <summary>varchar(n). T is string or string? (same runtime type).</summary>
    public static PropertyBuilder<T> Varchar<T>(this PropertyBuilder<T> p, int length) =>
        p.HasMaxLength(length).IsUnicode(false);

    /// <summary>nvarchar(n) — Myanmar Unicode text.</summary>
    public static PropertyBuilder<T> Nvarchar<T>(this PropertyBuilder<T> p, int length) =>
        p.HasMaxLength(length).IsUnicode();

    /// <summary>Enum stored as its camelCase name in a varchar(<paramref name="length"/>) column.</summary>
    public static PropertyBuilder<TEnum> CamelString<TEnum>(this PropertyBuilder<TEnum> p, int length)
        where TEnum : struct, Enum =>
        p.HasConversion(new CamelCaseEnumConverter<TEnum>()).HasMaxLength(length).IsUnicode(false);

    public static PropertyBuilder<TEnum?> CamelString<TEnum>(this PropertyBuilder<TEnum?> p, int length)
        where TEnum : struct, Enum =>
        p.HasConversion(new CamelCaseEnumConverter<TEnum>()).HasMaxLength(length).IsUnicode(false);

    /// <summary>
    /// Shared shape of every synced tenant table (schema.sql conventions):
    /// NONCLUSTERED PK on Id, CLUSTERED CX_{table} (TenantId, CreatedAt),
    /// rowversion Version and, optionally, the IX_{table}_Pull (TenantId, Version) index.
    /// </summary>
    public static EntityTypeBuilder<T> SyncedTable<T>(this EntityTypeBuilder<T> b, string table, bool pullIndex = true)
        where T : class, ISyncedRow
    {
        b.ToTable(table);
        b.HasKey(x => x.Id).HasName($"PK_{table}").IsClustered(false);
        b.HasIndex(x => new { x.TenantId, x.CreatedAt }).HasDatabaseName($"CX_{table}").IsClustered();
        b.Property(x => x.Version).IsRowVersion();
        if (pullIndex)
            b.HasIndex(x => new { x.TenantId, x.Version }).HasDatabaseName($"IX_{table}_Pull");
        return b;
    }
}

/// <summary>VoidReturn ⇄ "voidReturn" — the Dart enum name.</summary>
internal sealed class CamelCaseEnumConverter<TEnum>() : ValueConverter<TEnum, string>(
    v => ToCamel(v),
    s => Enum.Parse<TEnum>(s, ignoreCase: true))
    where TEnum : struct, Enum
{
    private static string ToCamel(TEnum value)
    {
        var name = value.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }
}
