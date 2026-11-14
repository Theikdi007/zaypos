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
Map<String, int> stockByProduct(Iterable<StockMovement> movements) =>
    {for (final e in stockLevels(movements).entries) e.key: e.value.onHandMilli};

/// Goods counted in: a restock or adjustment with a positive quantity. A
/// product with none has never had its stock recorded ("Stock မမှတ်ရသေး"),
/// so its ledger sum (≤ 0) means nothing yet — e.g. imported presets.
/// Server twin: UnitApplier.CheckNegativeStockAsync.
bool startsTracking(StockMovementType type, int qtyMilli) =>
    qtyMilli > 0 && (type == StockMovementType.restock || type == StockMovementType.adjustment);

/// Stock on hand plus whether the product's stock is tracked yet.
class StockLevel {
  const StockLevel(this.onHandMilli, {required this.tracked});
  static const untracked = StockLevel(0, tracked: false);

  final int onHandMilli;
  final bool tracked;

  @override
  bool operator ==(Object other) => other is StockLevel && other.onHandMilli == onHandMilli && other.tracked == tracked;
  @override
  int get hashCode => Object.hash(onHandMilli, tracked);
  @override
  String toString() => 'StockLevel($onHandMilli, tracked: $tracked)';
}

/// [StockLevel] per product id; soft-deleted rows ignored. Products without
/// live movements are absent (= [StockLevel.untracked]).
Map<String, StockLevel> stockLevels(Iterable<StockMovement> movements) {
  final out = <String, StockLevel>{};
  for (final m in movements) {
    if (m.deletedAt != null) continue;
    final prev = out[m.productId] ?? StockLevel.untracked;
    out[m.productId] = StockLevel(prev.onHandMilli + m.qtyMilli,
        tracked: prev.tracked || startsTracking(m.type, m.qtyMilli));
  }
  return out;
}

/// One movement per catalog line of [sale] (carrying variant/batch).
/// [sign] −1 = goods out (sale), +1 = goods back (void).
List<StockMovement> movementsForSale(
  Sale sale,
  StockMovementType type, {
  required int sign,
  String note = '',
  bool Function(SaleLine line)? where,
}) {
  final t = nowUtc();
  return [
    for (final l in sale.lines)
      if (l.productId != null && (where == null || where(l)))
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
