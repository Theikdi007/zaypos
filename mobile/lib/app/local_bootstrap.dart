import '../core/db/app_database.dart';
import '../core/db/mappers.dart';
import '../core/utils/ids.dart';
import '../features/auth/data/session.dart';
import '../features/customers/data/fake_customer_repository.dart';
import '../features/customers/data/fake_debt_repository.dart';
import '../features/devices/data/fake_device_repository.dart';
import '../features/inventory/data/fake_stock_repository.dart';
import '../features/products/data/fake_product_repository.dart';
import '../features/sales/data/fake_sales_repository.dart';

/// Who this install is, locally.
class LocalIdentity {
  const LocalIdentity({required this.tenantId, required this.deviceId, required this.shopName});
  final String tenantId;
  final String deviceId;
  final String shopName;
}

/// syncState keys of the local identity. TEMPORARY (Step 1 only): Step 2
/// replaces this with the signed-in tenant/device from secure storage.
abstract final class LocalIdentityKeys {
  static const tenantId = 'localTenantId';
  static const deviceId = 'localDeviceId';
}

/// Opens the local identity, creating the tenant + this device's row on first
/// launch. These rows are server-owned (created by /auth/register), so they
/// are written directly, without an outbox unit.
///
/// [seedSampleData] (debug builds): fills a brand-new database with the
/// design's sample shop so the app is usable before sign-in exists (Step 2
/// wipes the local DB when a real shop signs in).
Future<LocalIdentity> bootstrapLocalDatabase(AppDatabase db, {bool seedSampleData = false}) async {
  var tenantId = await db.readState(LocalIdentityKeys.tenantId);
  var deviceId = await db.readState(LocalIdentityKeys.deviceId);
  if (tenantId == null || deviceId == null) {
    final t = tenantId = newId();
    final device = seedDevice(t, lastSeq: seedSampleData ? 1032 : 0);
    deviceId = device.id;
    await db.transaction(() async {
      final now = nowUtc();
      await db.into(db.tenants).insert(TenantRow(
            id: t,
            tenantId: t,
            name: SessionNotifier.defaultShopName,
            templateId: 'grocery',
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.devices).insert(deviceRow(device));
      if (seedSampleData) await _seed(db, t, device.id);
      await db.writeState(LocalIdentityKeys.tenantId, t);
      await db.writeState(LocalIdentityKeys.deviceId, device.id);
    });
  }
  final tenant = await (db.select(db.tenants)..where((x) => x.id.equals(tenantId!))).getSingleOrNull();
  return LocalIdentity(
    tenantId: tenantId,
    deviceId: deviceId,
    shopName: tenant?.name ?? SessionNotifier.defaultShopName,
  );
}

/// Same data as the fake database (stock = opening counts, as there).
Future<void> _seed(AppDatabase db, String tenantId, String deviceId) async {
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
