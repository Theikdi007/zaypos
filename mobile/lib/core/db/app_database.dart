import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/customers/domain/debt_entry.dart';
import '../../features/inventory/domain/stock_movement.dart';
import '../../features/products/domain/product_modules.dart';
import '../../features/sales/domain/sale.dart';

part 'app_database.g.dart';

// Local database (docs/mobile/phase3-sync.md §3). One table per server table,
// same column names and meaning as the /sync/push and /sync/pull JSON.
// Ids: TEXT UUID. Money / milli-quantities: INTEGER. Times: INTEGER unix ms UTC.
// No `version` column: the pull cursor is stored once, in syncState.

/// DateTime <-> unix milliseconds (UTC). Drift's own DateTime column stores
/// seconds, which would break last-writer-wins comparisons.
class UtcMsConverter extends TypeConverter<DateTime, int> {
  const UtcMsConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

/// id, tenantId, createdAt, updatedAt, deletedAt — shared by every synced row.
mixin SyncedColumns on Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get createdAt => integer().map(const UtcMsConverter())();
  IntColumn get updatedAt => integer().map(const UtcMsConverter())();
  IntColumn get deletedAt => integer().map(const UtcMsConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------- tenancy

@DataClassName('TenantRow')
class Tenants extends Table with SyncedColumns {
  @override
  String get tableName => 'tenants';

  TextColumn get name => text()();
  TextColumn get templateId => text()();
  TextColumn get township => text().nullable()();
  TextColumn get plan => text().nullable()();
  IntColumn get planExpiresAt => integer().map(const UtcMsConverter()).nullable()();
}

@DataClassName('TenantFeatureRow')
class TenantFeatureFlags extends Table {
  @override
  String get tableName => 'tenantFeatures';

  TextColumn get tenantId => text()();
  TextColumn get featureKey => text()();
  BoolColumn get enabled => boolean()();
  IntColumn get updatedAt => integer().map(const UtcMsConverter())();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, featureKey};
}

@DataClassName('DeviceRow')
class Devices extends Table with SyncedColumns {
  @override
  String get tableName => 'devices';

  TextColumn get code => text()();
  TextColumn get name => text().nullable()();
  IntColumn get lastSeq => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncAt => integer().map(const UtcMsConverter()).nullable()();
}

// ---------------------------------------------------------------- catalog

@DataClassName('ProductRow')
@TableIndex(name: 'ix_products_barcode', columns: {#barcode})
class Products extends Table with SyncedColumns {
  @override
  String get tableName => 'products';

  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get unit => text().withDefault(const Constant(''))();
  TextColumn get barcode => text().nullable()();
  IntColumn get cost => integer().nullable()(); // null = unknown (BUG-61, schema 3)
  IntColumn get price => integer()();
  IntColumn get wholesalePrice => integer().nullable()();
  IntColumn get lowAlertMilli => integer()();
  IntColumn get warrantyMonths => integer().nullable()();
  IntColumn get expiryAlertDays => integer().nullable()();
  IntColumn get tint => integer()();
  TextColumn get initial => text()();
}

@DataClassName('ProductVariantRow')
class ProductVariants extends Table with SyncedColumns {
  @override
  String get tableName => 'productVariants';

  TextColumn get productId => text()();
  TextColumn get size => text()();
  TextColumn get color => text()();
}

/// Batch stock is derived (sum of stockMovements with this batchId), so there
/// is no quantity column (same as the server).
@DataClassName('ProductBatchRow')
class ProductBatches extends Table with SyncedColumns {
  @override
  String get tableName => 'productBatches';

  TextColumn get productId => text()();
  TextColumn get batchNo => text()();

  /// Calendar date as UTC midnight.
  IntColumn get expiryDate => integer().map(const UtcMsConverter()).nullable()();
}

@DataClassName('ProductSerialRow')
class ProductSerials extends Table with SyncedColumns {
  @override
  String get tableName => 'productSerials';

  TextColumn get productId => text()();
  TextColumn get serial => text()();
  TextColumn get status => textEnum<SerialStatus>()();
  TextColumn get saleLineId => text().nullable()();
}

// ---------------------------------------------------------------- ledgers

@DataClassName('StockMovementRow')
@TableIndex(name: 'ix_stockMovements_productId', columns: {#productId})
class StockMovements extends Table with SyncedColumns {
  @override
  String get tableName => 'stockMovements';

  TextColumn get productId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get batchId => text().nullable()();
  TextColumn get type => textEnum<StockMovementType>()();
  IntColumn get qtyMilli => integer()();
  TextColumn get saleId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().nullable()();
}

@DataClassName('CustomerRow')
class Customers extends Table with SyncedColumns {
  @override
  String get tableName => 'customers';

  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get address => text().nullable()();
  IntColumn get creditLimit => integer().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('DebtEntryRow')
@TableIndex(name: 'ix_debtEntries_customerId', columns: {#customerId})
class DebtEntries extends Table with SyncedColumns {
  @override
  String get tableName => 'debtEntries';

  TextColumn get customerId => text()();
  TextColumn get type => textEnum<DebtEntryType>()();
  IntColumn get amount => integer()();
  TextColumn get saleId => text().nullable()();
  TextColumn get saleNo => text().nullable()();
  TextColumn get method => textEnum<PaymentMethod>().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get deviceId => text().nullable()();
}

// ---------------------------------------------------------------- sales

@DataClassName('SaleRow')
@TableIndex(name: 'ix_sales_createdAt', columns: {#createdAt})
class Sales extends Table with SyncedColumns {
  @override
  String get tableName => 'sales';

  TextColumn get no => text()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  IntColumn get total => integer()();
  IntColumn get voidedAt => integer().map(const UtcMsConverter()).nullable()();

  /// Server arrival time; null until the sale comes back in a pull.
  IntColumn get syncedAt => integer().map(const UtcMsConverter()).nullable()();
}

@DataClassName('SaleLineRow')
@TableIndex(name: 'ix_saleLines_saleId', columns: {#saleId})
class SaleLines extends Table with SyncedColumns {
  @override
  String get tableName => 'saleLines';

  TextColumn get saleId => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get variantId => text().nullable()();
  TextColumn get batchId => text().nullable()();
  TextColumn get serialId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get qtyMilli => integer()();
  IntColumn get price => integer()();
  IntColumn get costSnapshot => integer().nullable()(); // null = unknown (BUG-61, schema 3)
  IntColumn get lineTotal => integer()();
}

@DataClassName('PaymentRow')
@TableIndex(name: 'ix_payments_saleId', columns: {#saleId})
class Payments extends Table with SyncedColumns {
  @override
  String get tableName => 'payments';

  TextColumn get saleId => text()();
  TextColumn get method => textEnum<PaymentMethod>()();
  IntColumn get amount => integer()();
  IntColumn get received => integer().nullable()();
}

@DataClassName('SyncIssueRow')
class SyncIssues extends Table with SyncedColumns {
  @override
  String get tableName => 'syncIssues';

  /// Server SyncIssueKind name (serialDoubleSold, negativeStock, …).
  TextColumn get kind => text()();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  /// Server's English text — never shown (BUG-26); the app builds the message from [kind] + [data].
  TextColumn get detail => text()();

  /// Structured fields as a JSON object string (barcode, productName, others, serial, amounts…). Null on old rows.
  TextColumn get data => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get resolvedAt => integer().map(const UtcMsConverter()).nullable()();
}

// ---------------------------------------------------------------- local only

/// Status of an outbox unit. `rejected` blocks every later unit (§1.3).
enum OutboxStatus { pending, rejected }

/// One committed unit of work waiting to be pushed, in push order.
@DataClassName('OutboxRow')
class Outbox extends Table {
  @override
  String get tableName => 'outbox';

  IntColumn get seq => integer().autoIncrement()();
  TextColumn get unitId => text().unique()();

  /// Server unit kind (UnitKind name).
  TextColumn get kind => text()();

  /// `{"sales":[…],"saleLines":[…],…}`
  TextColumn get rowsJson => text()();

  /// Unix ms UTC.
  IntColumn get clientTime => integer()();
  TextColumn get status => textEnum<OutboxStatus>().withDefault(Constant(OutboxStatus.pending.name))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Network / server error (retryable).
  TextColumn get lastError => text().nullable()();

  /// Server reason for `rejected` (English; only copied for Support, never shown — BUG-26).
  TextColumn get rejectReason => text().nullable()();

  /// Server reject code (fieldTooLong, notFound, …) — the shown message is built from it.
  TextColumn get rejectCode => text().nullable()();

  /// Reject fields as a JSON object string ({"field":"products.name","max":"150"}).
  TextColumn get rejectData => text().nullable()();
}

/// syncState key of the pull cursor (SyncStateKeys.pullCursor).
const pullCursorStateKey = 'pullCursor';

/// pullCursor, lastPushAt, lastPullAt, limitsJson, limitsEtag, …
@DataClassName('SyncStateRow')
class SyncState extends Table {
  @override
  String get tableName => 'syncState';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [
  Tenants,
  TenantFeatureFlags,
  Devices,
  Products,
  ProductVariants,
  ProductBatches,
  ProductSerials,
  StockMovements,
  Customers,
  DebtEntries,
  Sales,
  SaleLines,
  Payments,
  SyncIssues,
  Outbox,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  /// Tables that live only on this phone (never pulled from the server).
  static const localOnlyTables = {'outbox', 'syncState'};

  /// Schema versions whose migration adds columns to a PULLED table (BUG-43).
  ///
  /// The server sends a row again only when it changes, so rows pulled before
  /// the upgrade would keep the new columns empty for good. Upgrading past any
  /// version listed here resets the pull cursor, and the next sync downloads
  /// every row again with the new columns (rows of unsent local units are still
  /// protected by the merge, BUG-32). There is one cursor for all tables, so the
  /// reset re-downloads them all.
  ///
  /// RULE: a migration that adds a column to a table not in [localOnlyTables]
  /// must list its version here. test/db_migration_test.dart compares every
  /// pair of schema snapshots in drift_schemas/ and fails if one is missing.
  static const pullResetVersions = {2};

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2 (BUG-26): structured issue / reject fields; the app builds Burmese messages from them.
            await m.addColumn(syncIssues, syncIssues.data);
            await m.addColumn(outbox, outbox.rejectCode);
            await m.addColumn(outbox, outbox.rejectData);
          }
          if (from < 3) {
            // v3 (BUG-61): an unknown cost is NULL, a typed 0 is a real zero. Until now 0 meant unknown,
            // so 0 → NULL (the server's UnknownCostIsNull migration does the same; no re-download needed).
            await m.alterTable(TableMigration(products));
            await m.alterTable(TableMigration(saleLines));
            await customStatement('UPDATE products SET cost = NULL WHERE cost = 0');
            await customStatement('UPDATE saleLines SET costSnapshot = NULL WHERE costSnapshot = 0');
            await _unknownCostInUnsentUnits();
          }
          if (pullResetVersions.any((v) => v > from && v <= to)) {
            await writeState(pullCursorStateKey, '0');
          }
        },
      );

  /// v3: units written before the upgrade but not yet sent carry `cost: 0` for "unknown";
  /// the server now reads 0 as a real zero, so send null instead.
  Future<void> _unknownCostInUnsentUnits() async {
    const fields = {'products': 'cost', 'saleLines': 'costSnapshot'};
    for (final row in await customSelect('SELECT seq, rowsJson FROM outbox').get()) {
      final rows = (jsonDecode(row.read<String>('rowsJson')) as Map).cast<String, dynamic>();
      var changed = false;
      fields.forEach((table, field) {
        for (final r in (rows[table] as List? ?? const []).cast<Map<String, dynamic>>()) {
          if (r[field] == 0) {
            r[field] = null;
            changed = true;
          }
        }
      });
      if (changed) {
        await customUpdate('UPDATE outbox SET rowsJson = ? WHERE seq = ?',
            variables: [Variable.withString(jsonEncode(rows)), Variable.withInt(row.read<int>('seq'))],
            updates: {outbox});
      }
    }
  }

  // ---------------------------------------------------------------- syncState

  Future<String?> readState(String key) async =>
      (await (select(syncState)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeState(String key, String value) =>
      into(syncState).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
}
