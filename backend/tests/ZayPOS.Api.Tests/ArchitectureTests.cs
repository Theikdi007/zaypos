using FluentAssertions;

namespace ZayPOS.Api.Tests;

public class ArchitectureTests
{
    // Built from parts so this file does not match its own scan.
    private static readonly string Bypass = "Ignore" + "QueryFilters";
    private const string AllowedFile = "src/ZayPOS.Infrastructure/Auth/AuthRepository.cs";

    [Fact]
    public void Tenant_filter_is_bypassed_only_in_AuthRepository()
    {
        var root = BackendRoot();
        var hits = Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                        && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .Where(f => File.ReadAllText(f).Contains(Bypass, StringComparison.Ordinal))
            .Select(f => Path.GetRelativePath(root, f).Replace(Path.DirectorySeparatorChar, '/'))
            .ToList();

        hits.Should().Equal([AllowedFile], $"{Bypass} may only be used for pre-tenant auth lookups");
    }

    internal static string BackendRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "ZayPOS.slnx"))) return dir.FullName;
        throw new InvalidOperationException("backend/ZayPOS.slnx not found above the test output folder.");
    }
}
