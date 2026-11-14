import 'package:drift/drift.dart';

import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../../../core/utils/ids.dart';
import '../domain/sale.dart';
import 'sales_repository.dart';

class DriftSalesRepository implements SalesRepository {
  DriftSalesRepository(this.db, {required this.deviceId});
  final AppDatabase db;

  /// Stamped on sales rung up on this phone.
  final String deviceId;

  /// Re-runs [load] whenever sales, lines or payments change.
  Stream<T> _watchSales<T>(Future<T> Function() load) => db
      .customSelect('SELECT 1', readsFrom: {db.sales, db.saleLines, db.payments})
      .watch()
      .asyncMap((_) => load());

  /// Sales matching [where] with their lines and payments, newest first.
  Future<List<Sale>> loadSales({Expression<bool> Function(Sales s)? where}) async {
    final q = db.select(db.sales)
      ..where((s) => s.deletedAt.isNull() & (where?.call(s) ?? const Constant(true)))
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt), (s) => OrderingTerm.desc(s.no)]);
    final sales = await q.get();
    if (sales.isEmpty) return const [];
    final ids = sales.map((s) => s.id).toList();
    final lines = <String, List<SaleLineRow>>{};
    final payments = <String, List<PaymentRow>>{};
    // Chunked to stay under SQLite's bound-parameter limit.
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      for (final l in await (db.select(db.saleLines)
            ..where((l) => l.saleId.isIn(chunk))
            ..orderBy([(l) => OrderingTerm.asc(l.createdAt), (l) => OrderingTerm.asc(l.id)]))
          .get()) {
        (lines[l.saleId] ??= []).add(l);
      }
      for (final p in await (db.select(db.payments)..where((p) => p.saleId.isIn(chunk))).get()) {
        (payments[p.saleId] ??= []).add(p);
      }
    }
    return List.unmodifiable([
      for (final s in sales) saleFromRow(s, lines[s.id] ?? const [], payments[s.id] ?? const []),
    ]);
  }

  @override
  Stream<List<Sale>> watchAll() => _watchSales(loadSales);

  @override
  Stream<Sale?> watchById(String id) =>
      _watchSales(() async => (await loadSales(where: (s) => s.id.equals(id))).firstOrNull);

  @override
  Future<void> add(Sale sale) async {
    final rec = UnitRecorder.require();
    final s = saleRow(sale, deviceId: deviceId);
    await db.into(db.sales).insert(s);
    rec.record(WireTable.sales, saleWire(s));
    for (final l in sale.lines.map(saleLineRow)) {
      await db.into(db.saleLines).insert(l);
      rec.record(WireTable.saleLines, saleLineWire(l));
    }
    for (final p in sale.payments.map(paymentRow)) {
      await db.into(db.payments).insert(p);
      rec.record(WireTable.payments, paymentWire(p));
    }
  }

  @override
  Future<void> setVoided(String id, bool voided) async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.sales)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (current == null) throw StateError('Unknown sale $id');
    final t = nowUtc();
    final updated = current.copyWith(voidedAt: Value(voided ? t : null), updatedAt: t);
    await db.update(db.sales).replace(updated);
    rec.record(WireTable.sales, saleWire(updated));
  }
}
