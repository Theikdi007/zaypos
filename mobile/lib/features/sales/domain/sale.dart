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
    required this.costSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.productId,
    this.variantId,
    this.batchId,
    this.serialId,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String saleId;
  final String? productId;
  final String? variantId;
  final String? batchId;
  final String? serialId;

  /// Name snapshot at time of sale.
  final String name;
  final int qtyMilli;

  /// Kyats per unit.
  final int price;

  /// Unit cost (kyats) at the time of sale — profit never changes when the
  /// product's cost is edited later.
  final int costSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Kyats.
  int get total => Qty.lineTotal(price, qtyMilli);

  /// False when the cost was never entered (0: a product saved without a
  /// cost, or a Quick Sale item). Such lines are left out of profit (BUG-53).
  bool get costKnown => costSnapshot > 0;

  /// Kyats: (price − costSnapshot) × qty; 0 when the cost is unknown.
  int get profit => costKnown ? Qty.lineTotal(price - costSnapshot, qtyMilli) : 0;

  SaleLine copyWith({int? qtyMilli, int? price, DateTime? updatedAt, DateTime? Function()? deletedAt}) => SaleLine(
        id: id,
        tenantId: tenantId,
        saleId: saleId,
        productId: productId,
        variantId: variantId,
        batchId: batchId,
        serialId: serialId,
        name: name,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        price: price ?? this.price,
        costSnapshot: costSnapshot,
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

  /// Device-scoped receipt number, e.g. "A-1033" (see Device).
  final String no;
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

  /// Kyats (0 for a voided sale); lines with an unknown cost are left out.
  int get profit => voided ? 0 : lines.fold(0, (a, l) => a + l.profit);

  /// Lines whose cost is unknown (left out of [profit]); 0 for a voided sale.
  int get unknownCostLines => voided ? 0 : lines.where((l) => !l.costKnown).length;

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
