import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';

/// BUG-5: after a push is applied, this phone's future edit times are clamped
/// to serverTime + 5 min (as the server stored them), so later edits from
/// other phones are taken on pull.
void main() {
  test('phone clock 1 h ahead (its own clock too): serverTime from the push answer clamps the local edit', () async {
    final db = memoryDb();
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final real = DateTime.now().toUtc();
    final phone = real.add(const Duration(hours: 1));
    final api = FakeSyncApi()..serverTime = real;
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => phone);

    final p = Product(
      id: newId(), tenantId: shop.tenantId, name: 'A', cost: 1, price: 2, category: 'x', tint: 0, initial: 'A',
      createdAt: phone, updatedAt: phone,
    );
    await c.read(productServiceProvider).create(p);
    await engine.syncNow(manual: true);

    final clamped = (await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).updatedAt;
    expect(clamped.toUtc().millisecondsSinceEpoch, real.add(SyncStore.maxClockAhead).millisecondsSinceEpoch);

    final bRow = {
      ...productWire(await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()),
      'name': 'B',
      'updatedAt': real.add(const Duration(minutes: 10)).toIso8601String(),
    };
    api.pages.add(page({WireTable.products: [bRow]}, cursor: '00000000000000B1'));
    await engine.syncNow(manual: true);
    expect((await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).name, 'B');
  });

  test('a normal edit time (not ahead) is left as it is; an older pulled row still loses', () async {
    final db = memoryDb();
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final now = DateTime.now().toUtc();
    final api = FakeSyncApi()..serverTime = now;
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => now);
    final t = truncateToMs(now);
    final p = Product(
      id: newId(), tenantId: shop.tenantId, name: 'local', cost: 1, price: 2, category: 'x', tint: 0, initial: 'l',
      createdAt: t, updatedAt: t,
    );
    await c.read(productServiceProvider).create(p);
    await engine.syncNow(manual: true);
    final kept = (await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).updatedAt;
    expect(kept.toUtc(), t);

    final older = {
      ...productWire(await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()),
      'name': 'older',
      'updatedAt': t.subtract(const Duration(minutes: 1)).toIso8601String(),
    };
    api.pages.add(page({WireTable.products: [older]}, cursor: '00000000000000C1'));
    await engine.syncNow(manual: true);
    expect((await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).name, 'local');
  });
}
