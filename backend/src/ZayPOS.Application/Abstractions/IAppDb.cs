using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Infrastructure;

namespace ZayPOS.Application.Abstractions;

/// <summary>
/// The tenant-filtered EF Core context as the application layer sees it
/// (implemented by ZayPosDbContext; provider-agnostic).
/// </summary>
public interface IAppDb
{
    DbSet<T> Set<T>() where T : class;
    ChangeTracker ChangeTracker { get; }
    DatabaseFacade Database { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

public enum DbErrorKind { Other, Unique, ForeignKey, Check, Truncation, Concurrency }

/// <summary>Classifies provider exceptions (SQL Server error numbers live in Infrastructure).</summary>
public interface IDbErrors
{
    DbErrorKind Classify(Exception exception);
    /// <summary>Short, safe description (constraint name) for a rejected unit's reason.</summary>
    string Describe(Exception exception);
}
