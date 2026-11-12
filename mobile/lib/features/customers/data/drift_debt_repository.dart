import 'package:drift/drift.dart';

import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../domain/debt_entry.dart';
import 'debt_repository.dart';

class DriftDebtRepository implements DebtRepository {
  DriftDebtRepository(this.db, {required this.deviceId});
  final AppDatabase db;

  /// Stamped on entries written by this phone.
  final String deviceId;

  @override
  Stream<List<DebtEntry>> watchAll() => (db.select(db.debtEntries)
        ..where((e) => e.deletedAt.isNull())
        ..orderBy([(e) => OrderingTerm.desc(e.createdAt), (e) => OrderingTerm.desc(e.id)]))
      .map(debtFromRow)
      .watch();

  @override
  Future<void> add(DebtEntry entry) async {
    final rec = UnitRecorder.require();
    final row = debtRow(entry, deviceId: deviceId);
    await db.into(db.debtEntries).insert(row);
    rec.record(WireTable.debtEntries, debtWire(row));
  }
}
