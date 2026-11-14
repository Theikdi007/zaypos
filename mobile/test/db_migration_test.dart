import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';

import 'generated_migrations/schema.dart';

/// Drift schema migrations (drift_schemas/app). v2 = BUG-26 issue / reject fields.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2: the schema matches a fresh v2 database', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
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
    await verifier.migrateAndValidate(db, 2);
    final issue = await db.select(db.syncIssues).getSingle();
    expect((issue.kind, issue.data), ('duplicateBarcode', null));
    final unit = await db.select(db.outbox).getSingle();
    expect((unit.rejectReason, unit.rejectCode, unit.rejectData), ('products.name is required.', null, null));
    await db.close();
  });
}
