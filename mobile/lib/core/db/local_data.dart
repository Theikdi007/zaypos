import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/customers/data/fake_customer_repository.dart';
import '../../features/customers/data/fake_debt_repository.dart';
import '../../features/inventory/data/fake_stock_repository.dart';
import '../../features/products/data/fake_product_repository.dart';
import '../../features/sales/data/fake_sales_repository.dart';
import '../utils/ids.dart';
import 'app_database.dart';
import 'database_provider.dart';
import 'mappers.dart';

/// syncState keys that describe the database itself.
abstract final class LocalStateKeys {
  /// Install marker: equals the deviceId in secure storage. Missing = the app
  /// was (re)installed, so secure-storage leftovers (iOS Keychain survives
  /// uninstall) are stale.
  static const installDeviceId = 'installDeviceId';

  /// Whose data the local tables hold.
  static const ownerTenantId = 'ownerTenantId';
  static const ownerPhone = 'ownerPhone';
  static const ownerDemo = 'ownerDemo';
}

/// The shop whose rows are in the local database.
class LocalOwner {
  const LocalOwner({required this.tenantId, required this.phone, required this.isDemo});
  final String tenantId;
  final String phone;

  /// Debug-only sample shop (never synced).
  final bool isDemo;
}

/// What signing in to [phone] would do to the local data.
enum SignInCheck {
  /// Same shop as the local data: everything is kept.
  sameShop,

  /// Different shop (or demo / unknown data) with an empty outbox: every
  /// local table is wiped after the server accepts the sign-in.
  replace,

  /// Different shop but the outbox still has unpushed units: refused.
  refuse,
}

/// Thrown when local data would be replaced while the outbox is not empty.
class OutboxNotEmptyException implements Exception {
  const OutboxNotEmptyException(this.pending);
  final int pending;

  @override
  String toString() => 'OutboxNotEmptyException($pending units not pushed)';
}

/// Guards the local database across sign-ins (docs/mobile/phase3-sync.md §5.4, §6).
class LocalData {
  LocalData(this.db);
  final AppDatabase db;

  /// Outbox units not yet pushed (pending + rejected).
  Future<int> pendingUnits() async {
    final n = db.outbox.seq.count();
    return (await (db.selectOnly(db.outbox)..addColumns([n])).getSingle()).read(n) ?? 0;
  }

  Future<LocalOwner?> owner() async {
    final tenantId = await db.readState(LocalStateKeys.ownerTenantId);
    if (tenantId == null) return null;
    return LocalOwner(
      tenantId: tenantId,
      phone: await db.readState(LocalStateKeys.ownerPhone) ?? '',
      isDemo: await db.readState(LocalStateKeys.ownerDemo) == 'true',
    );
  }

  /// Decided BEFORE any network call, so a refused sign-in never registers
  /// this phone with another shop. [phone] is E.164; null = a new shop
  /// (register) or the demo shop.
  Future<SignInCheck> check(String? phone) async {
    final o = await owner();
    if (o != null && !o.isDemo && phone != null && o.phone == phone) return SignInCheck.sameShop;
    return await pendingUnits() > 0 ? SignInCheck.refuse : SignInCheck.replace;
  }

  /// Makes the local database belong to [tenantId]: same shop → kept;
  /// otherwise every table except the outbox is wiped (refused with
  /// [OutboxNotEmptyException] if the outbox has units). Then records the
  /// owner, the tenant row and this device's row (lastSeq never moves back).
  Future<void> adopt({
    required String tenantId,
    required String phone,
    required String shopName,
    required String templateId,
    String? plan,
    required String deviceId,
    required String deviceCode,
    required int deviceLastSeq,
    bool isDemo = false,
  }) =>
      db.transaction(() async {
        final o = await owner();
        final same = o != null && o.tenantId == tenantId && o.isDemo == isDemo;
        if (!same) {
          final pending = await pendingUnits();
          if (pending > 0) throw OutboxNotEmptyException(pending);
          await wipeAllExceptOutbox();
        }
        await db.writeState(LocalStateKeys.ownerTenantId, tenantId);
        await db.writeState(LocalStateKeys.ownerPhone, phone);
        await db.writeState(LocalStateKeys.ownerDemo, '$isDemo');

        final now = nowUtc();
        final tenant = await (db.select(db.tenants)..where((t) => t.id.equals(tenantId))).getSingleOrNull();
        await db.into(db.tenants).insertOnConflictUpdate(TenantRow(
              id: tenantId,
              tenantId: tenantId,
              name: shopName,
              templateId: templateId,
              township: tenant?.township,
              plan: plan ?? tenant?.plan,
              planExpiresAt: tenant?.planExpiresAt,
              createdAt: tenant?.createdAt ?? now,
              updatedAt: tenant?.updatedAt ?? now,
            ));
        final device = await (db.select(db.devices)..where((d) => d.id.equals(deviceId))).getSingleOrNull();
        await db.into(db.devices).insertOnConflictUpdate(DeviceRow(
              id: deviceId,
              tenantId: tenantId,
              code: deviceCode,
              name: device?.name,
              lastSeq: device == null || device.lastSeq < deviceLastSeq ? deviceLastSeq : device.lastSeq,
              lastSyncAt: device?.lastSyncAt,
              createdAt: device?.createdAt ?? now,
              updatedAt: now,
            ));
      });

  /// Deletes every row of every table except the outbox (syncState too —
  /// the pull cursor must restart at 0 for a new shop), keeping only the
  /// install marker.
  Future<void> wipeAllExceptOutbox() => db.transaction(() async {
        final marker = await db.readState(LocalStateKeys.installDeviceId);
        for (final table in db.allTables) {
          if (table.actualTableName == db.outbox.actualTableName) continue;
          await db.delete(table).go();
        }
        if (marker != null) await db.writeState(LocalStateKeys.installDeviceId, marker);
      });

  /// Debug only: opens the sample shop (seeded on first use). Same rule as a
  /// sign-in: replaces other local data only if the outbox is empty.
  Future<String> openDemo({required String deviceId, required bool releaseMode}) async {
    if (releaseMode) throw StateError('The demo shop does not exist in release builds.');
    final o = await owner();
    if (o != null && o.isDemo) return o.tenantId;
    final tenantId = newId();
    await adopt(
      tenantId: tenantId,
      phone: '',
      shopName: demoShopName,
      templateId: 'grocery',
      deviceId: deviceId,
      deviceCode: 'A',
      deviceLastSeq: 1032,
      isDemo: true,
    );
    await seedSampleShop(db, tenantId: tenantId, deviceId: deviceId, releaseMode: releaseMode);
    return tenantId;
  }

  static const demoShopName = 'ရွှေဝါ ကုန်စုံဆိုင် (Demo)';
}

/// The design's sample shop (products, opening stock, customers, debt, ~700
/// sales), written straight into the tables: no outbox units, never synced.
///
/// Impossible in release builds: [releaseMode] trips the assert in debug
/// and throws at runtime; callers also guard with `kReleaseMode` so the
/// call is compiled out of release builds.
Future<void> seedSampleShop(
  AppDatabase db, {
  required String tenantId,
  required String deviceId,
  bool releaseMode = kReleaseMode,
}) async {
  assert(!releaseMode, 'Sample data must never be seeded in a release build.');
  if (releaseMode) throw StateError('Sample data must never be seeded in a release build.');
  final sales = seedSales(tenantId);
  await db.batch((b) {
    b.insertAll(db.products, seedProducts(tenantId).map(productRow));
    b.insertAll(db.stockMovements, seedStock(tenantId).map((m) => movementRow(m, deviceId: deviceId)));
    b.insertAll(db.customers, seedCustomers(tenantId).map(customerRow));
    b.insertAll(db.debtEntries, seedDebt(tenantId).map((e) => debtRow(e, deviceId: deviceId)));
    b.insertAll(db.sales, sales.map((s) => saleRow(s, deviceId: deviceId)));
    b.insertAll(db.saleLines, [for (final s in sales) ...s.lines.map(saleLineRow)]);
    b.insertAll(db.payments, [for (final s in sales) ...s.payments.map(paymentRow)]);
  });
}

final localDataProvider = Provider<LocalData>((ref) => LocalData(ref.watch(appDatabaseProvider)));
