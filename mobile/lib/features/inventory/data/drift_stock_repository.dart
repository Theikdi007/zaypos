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
  Stream<Map<String, int>> watchStockByProduct() {
    final m = db.stockMovements;
    final sum = m.qtyMilli.sum();
    final q = db.selectOnly(m)
      ..addColumns([m.productId, sum])
      ..where(m.deletedAt.isNull())
      ..groupBy([m.productId]);
    return q.watch().map((rows) => {for (final r in rows) r.read(m.productId)!: r.read(sum) ?? 0});
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
