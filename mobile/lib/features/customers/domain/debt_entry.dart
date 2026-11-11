import '../../sales/domain/sale.dart';

enum DebtEntryType { creditSale, payment, adjustment }

/// Append-only debt ledger row. Balance = sum of [effect] over live entries.
class DebtEntry {
  const DebtEntry({
    required this.id,
    required this.tenantId,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.saleId,
    this.saleNo,
    this.method,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String customerId;
  final DebtEntryType type;

  /// Kyats. Positive for creditSale/payment; signed for adjustment
  /// (+ increases what the customer owes, − decreases it).
  final int amount;
  final String? saleId;

  /// Receipt number snapshot, e.g. "A-1030" (sale may be outside the local window).
  final String? saleNo;

  /// How a payment was received.
  final PaymentMethod? method;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Signed change to the customer's balance.
  int get effect => switch (type) {
        DebtEntryType.creditSale => amount,
        DebtEntryType.payment => -amount,
        DebtEntryType.adjustment => amount,
      };

  /// System reversal of a voided credit sale — kept in the ledger, hidden
  /// from the customer's history list.
  bool get isSaleReversal => type == DebtEntryType.adjustment && saleId != null;

  /// History row title ("အကြွေးဝယ် · #A-1030", "ငွေပြန်ဆပ် · ငွေသား").
  String get title => switch (type) {
        DebtEntryType.creditSale => 'အကြွေးဝယ် · #${saleNo ?? ''}',
        DebtEntryType.payment => 'ငွေပြန်ဆပ် · ${(method ?? PaymentMethod.cash).label}',
        DebtEntryType.adjustment => note ?? '',
      };

  DebtEntry copyWith({String? Function()? note, DateTime? updatedAt, DateTime? Function()? deletedAt}) => DebtEntry(
        id: id,
        tenantId: tenantId,
        customerId: customerId,
        type: type,
        amount: amount,
        saleId: saleId,
        saleNo: saleNo,
        method: method,
        note: note != null ? note() : this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// Balance owed from a ledger (soft-deleted rows ignored).
int debtBalance(Iterable<DebtEntry> entries) =>
    entries.where((e) => e.deletedAt == null).fold(0, (a, e) => a + e.effect);
