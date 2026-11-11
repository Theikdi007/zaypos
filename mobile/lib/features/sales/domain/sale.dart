import '../../../core/utils/qty.dart';

enum PaymentMethod {
  cash('ငွေသား'),
  kbz('KBZPay'),
  wave('WavePay'),
  debt('အကြွေး');

  const PaymentMethod(this.label);
  final String label;
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.tenantId,
    required this.saleId,
    required this.name,
    required this.qtyMilli,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.productId,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String saleId;
  final String? productId;

  /// Name snapshot at time of sale.
  final String name;
  final int qtyMilli;

  /// Kyats per unit.
  final int price;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Kyats.
  int get total => Qty.lineTotal(price, qtyMilli);

  SaleLine copyWith({int? qtyMilli, int? price, DateTime? updatedAt, DateTime? Function()? deletedAt}) => SaleLine(
        id: id,
        tenantId: tenantId,
        saleId: saleId,
        productId: productId,
        name: name,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        price: price ?? this.price,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// Tender received for a sale (cash / wallet). Credit sales have no
/// Payment — they create a DebtEntry(creditSale) instead.
class Payment {
  const Payment({
    required this.id,
    required this.tenantId,
    required this.saleId,
    required this.method,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.received,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String saleId;
  final PaymentMethod method;

  /// Kyats applied to the sale.
  final int amount;

  /// Kyats handed over (cash only); change = received − amount.
  final int? received;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  int? get change => received == null ? null : received! - amount;

  Payment copyWith({int? amount, int? Function()? received, DateTime? updatedAt, DateTime? Function()? deletedAt}) =>
      Payment(
        id: id,
        tenantId: tenantId,
        saleId: saleId,
        method: method,
        amount: amount ?? this.amount,
        received: received != null ? received() : this.received,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.tenantId,
    required this.no,
    required this.method,
    required this.lines,
    required this.createdAt,
    required this.updatedAt,
    this.payments = const [],
    this.customerId,
    this.customerName,
    this.voidedAt,
    this.syncedAt,
    this.deletedAt,
  });

  final String id;
  final String tenantId;

  /// Human receipt number (#1030).
  final int no;
  final PaymentMethod method;
  final List<SaleLine> lines;
  final List<Payment> payments;
  final String? customerId;

  /// Customer name snapshot for display.
  final String? customerName;
  final DateTime? voidedAt;

  /// Null until the server has acknowledged this sale.
  final DateTime? syncedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get voided => voidedAt != null;
  bool get pending => syncedAt == null;
  int get itemCount => lines.length;

  /// Kyats.
  int get total => lines.fold(0, (a, l) => a + l.total);

  /// Cash received (if any) for the receipt.
  int? get received {
    for (final p in payments) {
      if (p.received != null) return p.received;
    }
    return null;
  }

  int? get change => received == null ? null : received! - total;

  Sale copyWith({
    DateTime? Function()? voidedAt,
    DateTime? Function()? syncedAt,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Sale(
        id: id,
        tenantId: tenantId,
        no: no,
        method: method,
        lines: lines,
        payments: payments,
        customerId: customerId,
        customerName: customerName,
        voidedAt: voidedAt != null ? voidedAt() : this.voidedAt,
        syncedAt: syncedAt != null ? syncedAt() : this.syncedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}
