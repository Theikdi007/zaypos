import 'package:drift/drift.dart';

import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../domain/stock_movement.dart';
import 'stock_repository.dart';

class DriftStockRepository implements StockRepository {
  DriftStockRepository(this.db, {required this.deviceId});
  final AppDatabase db;

  /// Stamped on movements written by this phone.
  final String deviceId;

  @override
  Stream<List<StockMovement>> watchAll() => (db.select(db.stockMovements)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
      .map(movementFromRow)
      .watch();

  @override
  Stream<Map<String, StockLevel>> watchStockByProduct() {
    final m = db.stockMovements;
    final sum = m.qtyMilli.sum();
    // Same rule as [startsTracking]: any live restock/adjustment > 0.
    final countsIn = m.qtyMilli.isBiggerThanValue(0) &
        m.type.isIn([StockMovementType.restock.name, StockMovementType.adjustment.name]);
    final tracked = CaseWhenExpression<int>(cases: [CaseWhen(countsIn, then: const Constant(1))], orElse: const Constant(0)).max();
    final q = db.selectOnly(m)
      ..addColumns([m.productId, sum, tracked])
      ..where(m.deletedAt.isNull())
      ..groupBy([m.productId]);
    return q.watch().map((rows) => {
          for (final r in rows)
            r.read(m.productId)!: StockLevel(r.read(sum) ?? 0, tracked: (r.read(tracked) ?? 0) > 0),
        });
  }

  @override
  Future<void> addAll(List<StockMovement> movements) async {
    if (movements.isEmpty) return;
    final rec = UnitRecorder.require();
    for (final row in movements.map((x) => movementRow(x, deviceId: deviceId))) {
      await db.into(db.stockMovements).insert(row);
      rec.record(WireTable.stockMovements, movementWire(row));
    }
  }
}
