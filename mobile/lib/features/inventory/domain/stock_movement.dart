import '../../../core/utils/ids.dart';
import '../../sales/domain/sale.dart';

enum StockMovementType {
  /// Sold (negative qty).
  sale,

  /// Received from supplier / initial stock (positive qty).
  restock,

  /// Manual count correction or opening balance (signed).
  adjustment,

  /// Goods returned to stock because a sale was voided (positive qty).
  voidReturn,
}

/// Append-only stock ledger row. Current stock = sum of [qtyMilli].
class StockMovement {
  const StockMovement({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.type,
    required this.qtyMilli,
    required this.createdAt,
    required this.updatedAt,
    this.variantId,
    this.batchId,
    this.saleId,
    this.note = '',
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String? variantId;
  final String? batchId;
  final StockMovementType type;

  /// Signed milli-units (+ in, − out).
  final int qtyMilli;
  final String? saleId;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  StockMovement copyWith({String? note, DateTime? updatedAt, DateTime? Function()? deletedAt}) => StockMovement(
        id: id,
        tenantId: tenantId,
        productId: productId,
        variantId: variantId,
        batchId: batchId,
        type: type,
        qtyMilli: qtyMilli,
        saleId: saleId,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// Stock on hand (milli-units) from movements; soft-deleted rows ignored.
int stockOf(Iterable<StockMovement> movements) =>
    movements.where((m) => m.deletedAt == null).fold(0, (a, m) => a + m.qtyMilli);

/// Stock per product id.
Map<String, int> stockByProduct(Iterable<StockMovement> movements) {
  final out = <String, int>{};
  for (final m in movements) {
    if (m.deletedAt != null) continue;
    out[m.productId] = (out[m.productId] ?? 0) + m.qtyMilli;
  }
  return out;
}

/// One movement per catalog line of [sale] (carrying variant/batch).
/// [sign] −1 = goods out (sale), +1 = goods back (void).
List<StockMovement> movementsForSale(Sale sale, StockMovementType type, {required int sign, String note = ''}) {
  final t = nowUtc();
  return [
    for (final l in sale.lines)
      if (l.productId != null)
        StockMovement(
          id: newId(),
          tenantId: sale.tenantId,
          productId: l.productId!,
          variantId: l.variantId,
          batchId: l.batchId,
          type: type,
          qtyMilli: sign * l.qtyMilli,
          saleId: sale.id,
          note: note,
          createdAt: t,
          updatedAt: t,
        ),
  ];
}

/// Goods received (initial stock, supplier delivery).
StockMovement restockMovement({
  required String tenantId,
  required String productId,
  required int qtyMilli,
  String? variantId,
  String? batchId,
  String note = '',
}) {
  final t = nowUtc();
  return StockMovement(
    id: newId(),
    tenantId: tenantId,
    productId: productId,
    variantId: variantId,
    batchId: batchId,
    type: StockMovementType.restock,
    qtyMilli: qtyMilli,
    note: note,
    createdAt: t,
    updatedAt: t,
  );
}
