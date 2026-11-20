import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';

import 'generated_migrations/schema.dart';

/// Drift schema migrations (drift_schemas/app). v2 = BUG-26 issue / reject fields.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2: the schema matches a fresh v2 database', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion); // v1 → v2 → … current
    await db.close();
  });

  test('v1 → v2 keeps an existing issue and a rejected unit; the new columns start empty', () async {
    final schema = await verifier.schemaAt(1);
    final old = schema.rawDatabase;
    old.execute(
        "INSERT INTO syncIssues (id, tenantId, kind, entityTable, entityId, detail, createdAt, updatedAt) "
        "VALUES ('i1', 't1', 'duplicateBarcode', 'Products', 'p1', 'Barcode 1 is also used by: A.', 1, 1)");
    old.execute(
        "INSERT INTO outbox (unitId, kind, rowsJson, clientTime, status, rejectReason) "
        "VALUES ('u1', 'upsertProduct', '{}', 1, 'rejected', 'products.name is required.')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion); // v1 → v2 → … current
    final issue = await db.select(db.syncIssues).getSingle();
    expect((issue.kind, issue.data), ('duplicateBarcode', null));
    final unit = await db.select(db.outbox).getSingle();
    expect((unit.rejectReason, unit.rejectCode, unit.rejectData), ('products.name is required.', null, null));
    await db.close();
  });

  // ---------------------------------------------------------------- BUG-61: unknown cost = NULL (v3)

  test('v2 → v3: the schema matches a fresh v3 database', () async {
    final schema = await verifier.schemaAt(2);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  test('v2 → v3: a 0 cost (meant "unknown") becomes NULL, a real cost stays; unsent units are fixed too', () async {
    final schema = await verifier.schemaAt(2);
    final old = schema.rawDatabase;
    for (final (id, cost) in [('p0', 0), ('p1', 1500)]) {
      old.execute("INSERT INTO products (id, tenantId, createdAt, updatedAt, name, category, cost, price, lowAlertMilli, tint, initial) "
          "VALUES ('$id', 't1', 1, 1, 'n', 'c', $cost, 2000, 0, 0, 'n')");
    }
    for (final (id, cost) in [('l0', 0), ('l1', 1500)]) {
      old.execute("INSERT INTO saleLines (id, tenantId, createdAt, updatedAt, saleId, name, qtyMilli, price, costSnapshot, lineTotal) "
          "VALUES ('$id', 't1', 1, 1, 's1', 'n', 1000, 2000, $cost, 2000)");
    }
    final unsent = jsonEncode({
      'products': [{'id': 'p0', 'cost': 0}, {'id': 'p1', 'cost': 1500}],
      'saleLines': [{'id': 'l0', 'costSnapshot': 0}],
    });
    old.execute("INSERT INTO outbox (unitId, kind, rowsJson, clientTime) VALUES ('u1', 'checkout', '$unsent', 1)");
    old.execute("INSERT INTO outbox (unitId, kind, rowsJson, clientTime) VALUES ('u2', 'upsertCustomer', '{\"customers\":[]}', 1)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    final costs = {for (final p in await db.select(db.products).get()) p.id: p.cost};
    expect(costs, {'p0': null, 'p1': 1500});
    final lineCosts = {for (final l in await db.select(db.saleLines).get()) l.id: l.costSnapshot};
    expect(lineCosts, {'l0': null, 'l1': 1500});
    final units = {for (final o in await db.select(db.outbox).get()) o.unitId: jsonDecode(o.rowsJson)};
    expect(units['u1'], {
      'products': [{'id': 'p0', 'cost': null}, {'id': 'p1', 'cost': 1500}],
      'saleLines': [{'id': 'l0', 'costSnapshot': null}],
    });
    expect(units['u2'], {'customers': []}, reason: 'other units untouched');
    await db.close();
  });

  // ---------------------------------------------------------------- BUG-43: pull cursor reset

  test('v1 → v2 resets the pull cursor, so the next sync re-downloads the issues with their new data', () async {
    final schema = await verifier.schemaAt(1);
    final old = schema.rawDatabase;
    old.execute("INSERT INTO syncState (key, value) VALUES ('pullCursor', '00000000000a1b2c')");
    old.execute("INSERT INTO syncState (key, value) VALUES ('initialSyncDone', 'true')");
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion); // v1 → v2 → … current
    expect(await db.readState(SyncStateKeys.pullCursor), '0');
    expect(await SyncStore(db, tenantId: 't1', deviceId: 'd1').cursor(), '0');
    expect(await db.readState(SyncStateKeys.initialSyncDone), 'true', reason: 'only the cursor is reset');
    await db.close();
  });

  test('a fresh install does not write a cursor (onCreate)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(await db.readState(SyncStateKeys.pullCursor), isNull);
    await db.close();
  });

  group('RULE: a migration that adds columns to a pulled table resets the pull cursor', () {
    final snapshots = loadSchemaSnapshots();

    test('every schema version has a snapshot in drift_schemas/app (run drift_dev schema dump)', () {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(snapshots.keys.toSet(), {for (var v = 1; v <= db.schemaVersion; v++) v});
    });

    test('every version that adds a column or table to a pulled table is in AppDatabase.pullResetVersions', () {
      expect(missingPullResets(snapshots, AppDatabase.pullResetVersions, AppDatabase.localOnlyTables), isEmpty,
          reason: 'add the version to AppDatabase.pullResetVersions (BUG-43)');
    });

    test('the check catches a forgotten version (v2 adds syncIssues.data)', () {
      expect(missingPullResets(snapshots, const {}, AppDatabase.localOnlyTables), {2: ['syncIssues.data']});
      expect(missingPullResets(snapshots, const {}, const {'outbox', 'syncState', 'syncIssues'}), isEmpty,
          reason: 'outbox columns alone (local-only) need no reset');
    });
  });
}

/// version → {table → column names}, from drift_schemas/app/drift_schema_vN.json.
Map<int, Map<String, Set<String>>> loadSchemaSnapshots() {
  final out = <int, Map<String, Set<String>>>{};
  for (final f in Directory('drift_schemas/app').listSync().whereType<File>()) {
    final m = RegExp(r'drift_schema_v(\d+)\.json$').firstMatch(f.path);
    if (m == null) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    out[int.parse(m[1]!)] = {
      for (final e in (j['entities'] as List).cast<Map<String, dynamic>>())
        if (e['type'] == 'table')
          (e['data']['name'] as String): {
            for (final c in (e['data']['columns'] as List).cast<Map<String, dynamic>>()) c['name'] as String,
          },
    };
  }
  return out;
}

/// Versions that add a column (or a new table) to a table outside [localOnly] but are not in [resets],
/// with what they add ("table.column", or "table" for a new table).
Map<int, List<String>> missingPullResets(
    Map<int, Map<String, Set<String>>> snapshots, Set<int> resets, Set<String> localOnly) {
  final out = <int, List<String>>{};
  final versions = snapshots.keys.toList()..sort();
  for (var i = 1; i < versions.length; i++) {
    final before = snapshots[versions[i - 1]]!, after = snapshots[versions[i]]!;
    final added = <String>[
      for (final MapEntry(key: t, value: cols) in after.entries)
        if (!localOnly.contains(t))
          if (!before.containsKey(t)) t else for (final c in cols.difference(before[t]!)) '$t.$c',
    ];
    if (added.isNotEmpty && !resets.contains(versions[i])) out[versions[i]] = added;
  }
  return out;
}
