using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Application.Abstractions;

namespace ZayPOS.Infrastructure.Persistence;

/// <summary>SQL Server error numbers → <see cref="DbErrorKind"/>.</summary>
internal sealed class SqlServerDbErrors : IDbErrors
{
    public DbErrorKind Classify(Exception exception)
    {
        if (exception is DbUpdateConcurrencyException) return DbErrorKind.Concurrency;
        return Sql(exception) switch
        {
            { Number: 2601 or 2627 } => DbErrorKind.Unique,
            { Number: 547 } e when e.Message.Contains("FOREIGN KEY", StringComparison.OrdinalIgnoreCase) => DbErrorKind.ForeignKey,
            { Number: 547 } => DbErrorKind.Check,
            { Number: 8152 or 2628 } => DbErrorKind.Truncation,
            _ => DbErrorKind.Other,
        };
    }

    public string Describe(Exception exception)
    {
        var message = Sql(exception)?.Message ?? exception.Message;
        return message.Length <= 300 ? message : message[..300];
    }

    private static SqlException? Sql(Exception e) => e as SqlException ?? e.InnerException as SqlException;
}
