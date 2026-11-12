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
  Stream<Map<String, int>> watchBalances() {
    final e = db.debtEntries;
    final effect = CaseWhenExpression<int>(
      cases: [CaseWhen(e.type.equalsValue(DebtEntryType.payment), then: -e.amount)],
      orElse: e.amount,
    );
    final sum = effect.sum();
    final q = db.selectOnly(e)
      ..addColumns([e.customerId, sum])
      ..where(e.deletedAt.isNull())
      ..groupBy([e.customerId]);
    return q.watch().map((rows) => {for (final r in rows) r.read(e.customerId)!: r.read(sum) ?? 0});
  }

  @override
  Future<void> add(DebtEntry entry) async {
    final rec = UnitRecorder.require();
    final row = debtRow(entry, deviceId: deviceId);
    await db.into(db.debtEntries).insert(row);
    rec.record(WireTable.debtEntries, debtWire(row));
  }
}
