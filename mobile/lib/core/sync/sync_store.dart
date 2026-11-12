import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/ids.dart';
import 'sync_api.dart';
import 'wire.dart';
import 'wire_decode.dart';

/// syncState keys (docs/mobile/phase3-sync.md §3.2).
abstract final class SyncStateKeys {
  static const pullCursor = 'pullCursor';
  static const lastPushAt = 'lastPushAt';
  static const lastPullAt = 'lastPullAt';

  /// The first full download (§5.4) completed for this shop.
  static const initialSyncDone = 'initialSyncDone';
}

class OutboxCounts {
  const OutboxCounts({this.pending = 0, this.rejected = 0});
  final int pending;
  final int rejected;
  int get total => pending + rejected;
}

/// Text columns the owner may correct on a rejected unit (§7), per table.
/// The JSON key, the Drift column and the server field have the same name.
const editableColumns = <String, List<String>>{
  WireTable.products: ['name', 'category', 'unit', 'barcode'],
  WireTable.customers: ['name', 'phone', 'address', 'note'],
  WireTable.productVariants: ['size', 'color'],
  WireTable.productBatches: ['batchNo'],
  WireTable.productSerials: ['serial'],
  WireTable.sales: ['customerName'],
  WireTable.saleLines: ['name'],
  WireTable.stockMovements: ['note'],
  WireTable.debtEntries: ['note'],
};

/// table → row id → column → new value.
typedef UnitEdits = Map<String, Map<String, Map<String, String?>>>;

/// Local-database side of the sync engine: outbox batches, push results,
/// pull merges (§5.2, §5.3) and rejected-unit repair (§7).
class SyncStore {
  SyncStore(this.db, {required this.tenantId, required this.deviceId});

  final AppDatabase db;
  final String tenantId;

  /// This phone: its own devices row keeps the higher lastSeq.
  final String deviceId;

  WireDecoder get _decode => WireDecoder(tenantId);

  static Map<String, dynamic> rowsOf(OutboxRow o) => (jsonDecode(o.rowsJson) as Map).cast<String, dynamic>();

  static Iterable<(String table, String id)> _ids(Map<String, dynamic> rows) sync* {
    for (final e in rows.entries) {
      for (final r in e.value as List) {
        final m = r as Map;
        final id = (m['id'] ?? m['featureKey'])?.toString();
        if (id != null) yield (e.key, id);
      }
    }
  }

  // ---------------------------------------------------------------- state

  Future<String> cursor() async => await db.readState(SyncStateKeys.pullCursor) ?? '0';

  Future<bool> initialSyncDone() async => await db.readState(SyncStateKeys.initialSyncDone) == 'true';

  Future<void> markInitialSyncDone() => db.writeState(SyncStateKeys.initialSyncDone, 'true');

  Future<DateTime?> lastSyncAt() async {
    final s = await db.readState(SyncStateKeys.lastPullAt);
    return s == null ? null : DateTime.tryParse(s)?.toUtc();
  }

  // ---------------------------------------------------------------- push

  /// The next units to push, oldest first, stopping at the first rejected one
  /// (it blocks every later unit, §1.3).
  Future<List<OutboxRow>> nextBatch([int max = 50]) async {
    final rows = await (db.select(db.outbox)
          ..orderBy([(o) => OrderingTerm.asc(o.seq)])
          ..limit(max))
        .get();
    return rows.takeWhile((o) => o.status == OutboxStatus.pending).toList();
  }

  /// Applies the server's answer for [batch] in ONE transaction. Returns true
  /// if a unit was rejected (pushing must stop).
  ///
  /// - applied → the outbox row goes.
  /// - skipped (only a voidSale whose sales are already in that state on the
  ///   server) → the outbox row goes and so do the unit's ledger rows
  ///   (stock movements, debt entries, payments) that the server did not keep.
  ///   The sale row itself stays: its state already equals the server's, and a
  ///   pull would not bring it back if it was pulled before.
  /// - rejected → status rejected + reason; later units are not touched.
  Future<bool> applyResults(List<OutboxRow> batch, List<UnitResult> results) => db.transaction(() async {
        final byUnit = {for (final r in results) r.unitId: r};
        for (final o in batch) {
          final r = byUnit[o.unitId];
          if (r == null) return false; // not answered: stays pending
          switch (r.outcome) {
            case UnitOutcome.applied:
              await _deleteOutbox(o.seq);
            case UnitOutcome.skipped:
              await _dropLedgerRows(rowsOf(o));
              await _deleteOutbox(o.seq);
            case UnitOutcome.rejected:
              await (db.update(db.outbox)..where((x) => x.seq.equals(o.seq))).write(OutboxCompanion(
                    status: const Value(OutboxStatus.rejected),
                    rejectReason: Value(r.reason ?? 'rejected'),
                    lastError: const Value(null),
                  ));
              return true;
          }
        }
        await db.writeState(SyncStateKeys.lastPushAt, nowUtc().toIso8601String());
        return false;
      });

  Future<void> _deleteOutbox(int seq) => (db.delete(db.outbox)..where((x) => x.seq.equals(seq))).go();

  Future<void> _dropLedgerRows(Map<String, dynamic> rows) async {
    for (final (table, id) in _ids(rows)) {
      switch (table) {
        case WireTable.stockMovements:
          await (db.delete(db.stockMovements)..where((x) => x.id.equals(id))).go();
        case WireTable.debtEntries:
          await (db.delete(db.debtEntries)..where((x) => x.id.equals(id))).go();
        case WireTable.payments:
          await (db.delete(db.payments)..where((x) => x.id.equals(id))).go();
      }
    }
  }

  /// Network / server failure: the batch stays pending with the error.
  Future<void> markFailed(List<OutboxRow> batch, String error) => db.transaction(() async {
        for (final o in batch) {
          await (db.update(db.outbox)..where((x) => x.seq.equals(o.seq)))
              .write(OutboxCompanion(attempts: Value(o.attempts + 1), lastError: Value(error)));
        }
      });

  // ---------------------------------------------------------------- pull

  /// Merges one pull page and saves its cursor in ONE transaction: a page is
  /// either fully merged with its cursor, or not at all. Returns rows merged.
  Future<int> mergePage(PullPage page) => db.transaction(() async {
        final unpushed = await _unpushedIds();
        var n = 0;
        for (final MapEntry(key: table, value: rows) in page.changes.entries) {
          for (final j in rows) {
            await _merge(table, j, unpushed);
            n++;
          }
        }
        await db.writeState(SyncStateKeys.pullCursor, page.cursor);
        await db.writeState(SyncStateKeys.lastPullAt, nowUtc().toIso8601String());
        return n;
      });

  /// "table:id" of every row in a unit not yet accepted by the server.
  Future<Set<String>> _unpushedIds() async => {
        for (final o in await db.select(db.outbox).get())
          for (final (t, id) in _ids(rowsOf(o))) '$t:$id',
      };

  /// §5.3 merge rules.
  Future<void> _merge(String table, Json j, Set<String> unpushed) async {
    final d = _decode;
    switch (table) {
      // Ledgers and issues: the server is the truth (sales.voidedAt included).
      case WireTable.sales:
        await db.into(db.sales).insertOnConflictUpdate(d.sale(j));
      case WireTable.saleLines:
        await db.into(db.saleLines).insertOnConflictUpdate(d.saleLine(j));
      case WireTable.payments:
        await db.into(db.payments).insertOnConflictUpdate(d.payment(j));
      case WireTable.stockMovements:
        await db.into(db.stockMovements).insertOnConflictUpdate(d.movement(j));
      case WireTable.debtEntries:
        await db.into(db.debtEntries).insertOnConflictUpdate(d.debt(j));
      case 'syncIssues':
        await db.into(db.syncIssues).insertOnConflictUpdate(d.issue(j));
      case WireTable.productSerials:
        await db.into(db.productSerials).insertOnConflictUpdate(d.serial(j));

      // Last-writer-wins, never over an unpushed local edit.
      case WireTable.products:
        final r = d.product(j);
        if (await _takes(table, db.products, r.id, r.updatedAt, unpushed)) await db.into(db.products).insertOnConflictUpdate(r);
      case WireTable.productVariants:
        final r = d.variant(j);
        if (await _takes(table, db.productVariants, r.id, r.updatedAt, unpushed)) {
          await db.into(db.productVariants).insertOnConflictUpdate(r);
        }
      case WireTable.productBatches:
        final r = d.batch(j);
        if (await _takes(table, db.productBatches, r.id, r.updatedAt, unpushed)) {
          await db.into(db.productBatches).insertOnConflictUpdate(r);
        }
      case WireTable.customers:
        final r = d.customer(j);
        if (await _takes(table, db.customers, r.id, r.updatedAt, unpushed)) await db.into(db.customers).insertOnConflictUpdate(r);
      case WireTable.tenants:
        final r = d.tenant(j);
        if (await _takes(table, db.tenants, r.id, r.updatedAt, unpushed)) await db.into(db.tenants).insertOnConflictUpdate(r);
      case WireTable.tenantFeatures:
        final r = d.feature(j);
        if (unpushed.contains('$table:${r.featureKey}')) return;
        final local = await (db.select(db.tenantFeatureFlags)
              ..where((f) => f.tenantId.equals(r.tenantId) & f.featureKey.equals(r.featureKey)))
            .getSingleOrNull();
        if (local == null || !r.updatedAt.isBefore(local.updatedAt)) {
          await db.into(db.tenantFeatureFlags).insertOnConflictUpdate(r);
        }

      // Devices: other phones as the server says; this phone's lastSeq never moves back.
      case WireTable.devices:
        var r = d.device(j);
        if (r.id == deviceId) {
          final local = await (db.select(db.devices)..where((x) => x.id.equals(r.id))).getSingleOrNull();
          if (local != null && local.lastSeq > r.lastSeq) r = r.copyWith(lastSeq: local.lastSeq);
        }
        await db.into(db.devices).insertOnConflictUpdate(r);

      default:
        // A table this app version does not know yet: ignore (forward compatible).
        break;
    }
  }

  /// pulled.updatedAt >= local.updatedAt and no unpushed unit contains the row.
  Future<bool> _takes(String table, TableInfo<Table, Object?> t, String id, DateTime pulled, Set<String> unpushed) async {
    if (unpushed.contains('$table:$id')) return false;
    final local = await db
        .customSelect('SELECT "updatedAt" FROM "${t.actualTableName}" WHERE "id" = ?', variables: [Variable.withString(id)])
        .getSingleOrNull();
    return local == null || pulled.millisecondsSinceEpoch >= local.read<int>('updatedAt');
  }

  /// A row the server returned outside a pull (e.g. a resolved issue).
  Future<void> mergeRow(String table, Json row) => db.transaction(() async => _merge(table, row, await _unpushedIds()));

  // ---------------------------------------------------------------- rejected units (§7)

  Future<OutboxRow?> unit(int seq) => (db.select(db.outbox)..where((o) => o.seq.equals(seq))).getSingleOrNull();

  /// "Edit, rebuild, set pending": writes [edits] to the local rows (only
  /// [editableColumns]; their updatedAt moves to now), rebuilds every row of
  /// the unit from the local tables, and queues it again under a NEW unitId
  /// (the server answers the old id with `rejected` forever).
  Future<void> resend(int seq, {UnitEdits edits = const {}}) => db.transaction(() async {
        final o = await unit(seq);
        if (o == null) throw StateError('No outbox unit $seq');
        final now = nowUtc();
        for (final MapEntry(key: table, value: byId) in edits.entries) {
          final allowed = editableColumns[table] ?? const [];
          for (final MapEntry(key: id, value: cols) in byId.entries) {
            for (final MapEntry(key: col, value: v) in cols.entries) {
              if (!allowed.contains(col)) throw ArgumentError('$table.$col cannot be edited');
              await db.customUpdate(
                'UPDATE "$table" SET "$col" = ?, "updatedAt" = ? WHERE "id" = ?',
                variables: [
                  v == null ? const Variable<String>(null) : Variable.withString(v),
                  Variable.withInt(now.millisecondsSinceEpoch),
                  Variable.withString(id),
                ],
                updates: {for (final t in db.allTables) if (t.actualTableName == table) t},
              );
            }
          }
        }
        final rebuilt = <String, List<Map<String, Object?>>>{};
        for (final MapEntry(key: table, value: rows) in rowsOf(o).entries) {
          rebuilt[table] = [
            for (final r in rows as List) await _localWire(table, (r as Map).cast<String, dynamic>()) ?? r.cast<String, Object?>(),
          ];
        }
        await (db.update(db.outbox)..where((x) => x.seq.equals(seq))).write(OutboxCompanion(
              unitId: Value(newId()),
              rowsJson: Value(jsonEncode(rebuilt)),
              status: const Value(OutboxStatus.pending),
              attempts: const Value(0),
              lastError: const Value(null),
              rejectReason: const Value(null),
            ));
      });

  /// The current local version of a recorded row, in wire shape (null = gone).
  Future<Map<String, Object?>?> _localWire(String table, Map<String, dynamic> recorded) async {
    final id = recorded['id'] as String? ?? '';
    return switch (table) {
      WireTable.products =>
        (await (db.select(db.products)..where((x) => x.id.equals(id))).getSingleOrNull()).let(productWire),
      WireTable.productVariants =>
        (await (db.select(db.productVariants)..where((x) => x.id.equals(id))).getSingleOrNull()).let(variantWire),
      WireTable.productBatches =>
        (await (db.select(db.productBatches)..where((x) => x.id.equals(id))).getSingleOrNull()).let(batchWire),
      WireTable.productSerials =>
        (await (db.select(db.productSerials)..where((x) => x.id.equals(id))).getSingleOrNull()).let(serialWire),
      WireTable.customers =>
        (await (db.select(db.customers)..where((x) => x.id.equals(id))).getSingleOrNull()).let(customerWire),
      WireTable.sales => (await (db.select(db.sales)..where((x) => x.id.equals(id))).getSingleOrNull()).let(saleWire),
      WireTable.saleLines =>
        (await (db.select(db.saleLines)..where((x) => x.id.equals(id))).getSingleOrNull()).let(saleLineWire),
      WireTable.payments =>
        (await (db.select(db.payments)..where((x) => x.id.equals(id))).getSingleOrNull()).let(paymentWire),
      WireTable.stockMovements =>
        (await (db.select(db.stockMovements)..where((x) => x.id.equals(id))).getSingleOrNull()).let(movementWire),
      WireTable.debtEntries =>
        (await (db.select(db.debtEntries)..where((x) => x.id.equals(id))).getSingleOrNull()).let(debtWire),
      WireTable.devices => (await (db.select(db.devices)..where((x) => x.id.equals(id))).getSingleOrNull()).let(deviceWire),
      WireTable.tenantFeatures => (await (db.select(db.tenantFeatureFlags)
                ..where((f) => f.featureKey.equals(recorded['featureKey'] as String? ?? '')))
              .getSingleOrNull())
          .let(tenantFeatureWire),
      _ => null,
    };
  }

  // ---------------------------------------------------------------- watchers (UI)

  Stream<OutboxCounts> watchCounts() => db.select(db.outbox).watch().map((rows) => OutboxCounts(
        pending: rows.where((o) => o.status == OutboxStatus.pending).length,
        rejected: rows.where((o) => o.status == OutboxStatus.rejected).length,
      ));

  Stream<List<OutboxRow>> watchRejected() => (db.select(db.outbox)
        ..where((o) => o.status.equalsValue(OutboxStatus.rejected))
        ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
      .watch();

  /// Issues the owner has not reviewed yet, newest first.
  Stream<List<SyncIssueRow>> watchOpenIssues() => (db.select(db.syncIssues)
        ..where((i) => i.resolvedAt.isNull() & i.deletedAt.isNull())
        ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
      .watch();
}

extension<T extends Object> on T? {
  R? let<R>(R Function(T) f) => this == null ? null : f(this as T);
}
