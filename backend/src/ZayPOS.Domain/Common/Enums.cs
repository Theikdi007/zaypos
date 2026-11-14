namespace ZayPOS.Domain.Common;

// Every enum is stored as its camelCase member name ("voidReturn", "inStock"),
// matching the Dart enum names and the CHECK constraints in schema.sql.

/// <summary>Dart <c>PaymentMethod</c>. <see cref="Debt"/> is only valid on <c>Sales.Method</c>.</summary>
public enum PaymentMethod { Cash, Kbz, Wave, Debt }

/// <summary>Dart <c>StockMovementType</c>.</summary>
public enum StockMovementType { Sale, Restock, Adjustment, VoidReturn }

/// <summary>Dart <c>DebtEntryType</c>.</summary>
public enum DebtEntryType { CreditSale, Payment, Adjustment }

/// <summary>Dart <c>SerialStatus</c>.</summary>
public enum SerialStatus { InStock, Sold }

public enum TenantPlan { Free, Pro }

public enum UserRole { Owner, Staff }

public enum OtpPurpose { Register, Reset }

public enum UnitOutcome { Applied, Skipped, Rejected }

public enum SubscriptionStatus { Pending, Approved, Rejected }

/// <summary>README §3.4.</summary>
public enum SyncIssueKind
{
    SerialDoubleSold,
    NegativeStock,
    DuplicateBarcode,
    CreditLimitExceeded,
    ClockSkew,
    TotalMismatch,
    /// <summary>Not in README §3.4: a sale's receipt number already existed (reinstall reused a device code).</summary>
    DuplicateReceiptNo,
    /// <summary>A second live in-stock IMEI / serial row with the same serial arrived (e.g. two phones received it offline). Both rows are kept.</summary>
    DuplicateSerial,
}
