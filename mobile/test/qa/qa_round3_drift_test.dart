// QA round 3 — Drift (real local database, in memory): what the BUG-12 fix puts in the outbox, that it never re-sends or
// changes existing module rows, the cleared low alert on the wire, and expiry after a Drift round trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';

import '../drift_helpers.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1);

  test('TC-PROD-NEW-6/7 Drift: receive() = ONE restock unit with ONLY the new IMEI / batch rows + the movement; '
      'existing module rows are not re-sent or changed', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R3 D', cost: 1, price: 2, category: 'x', tint: 0,
        initial: 'D', createdAt: t0, updatedAt: t0);
    final old = ProductSerial(id: newId(), tenantId: shop.tenantId, productId: p.id, serial: '900000000000001',
        status: SerialStatus.sold, createdAt: t0, updatedAt: t0);
    final oldBatch = ProductBatch(id: newId(), tenantId: shop.tenantId, productId: p.id, batchNo: 'OLD', qtyMilli: 0,
        expiryDate: DateTime.utc(2020, 1, 31), createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, serials: [old], batches: [oldBatch], initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(3), batchId: oldBatch.id),
    ]);
    await adb.delete(adb.outbox).go();
    final stock = c.read(stockServiceProvider);

    await stock.receive(productId: p.id, qtyMilli: Qty.units(2), serials: ['900000000000002', '900000000000003']);
    final nb = ProductBatch(id: newId(), tenantId: shop.tenantId, productId: p.id, batchNo: 'R3NEW', qtyMilli: Qty.units(6),
        expiryDate: DateTime.utc(2027, 3, 31), createdAt: nowUtc(), updatedAt: nowUtc());
    await stock.receive(productId: p.id, qtyMilli: Qty.units(6), newBatch: nb);
    await stock.receive(productId: p.id, qtyMilli: Qty.units(1), batchId: oldBatch.id);

    final units = await outbox(adb);
    expect(units.map((u) => u.kind), ['restock', 'restock', 'restock']);
    final r1 = rowsOf(units[0]);
    expect(r1.keys.toSet(), {'productSerials', 'stockMovements'});
    expect((r1['productSerials'] as List).map((s) => ((s as Map)['serial'], s['status'], s['productId'])).toSet(),
        {('900000000000002', 'inStock', p.id), ('900000000000003', 'inStock', p.id)});
    final m1 = (r1['stockMovements'] as List).single as Map;
    expect((m1['type'], m1['qtyMilli'], m1['productId']), ('restock', 2000, p.id));
    final r2 = rowsOf(units[1]);
    expect(r2.keys.toSet(), {'productBatches', 'stockMovements'});
    final b2 = (r2['productBatches'] as List).single as Map;
    expect((b2['id'], b2['batchNo'], b2['expiryDate']), (nb.id, 'R3NEW', '2027-03-31'));
    expect(((r2['stockMovements'] as List).single as Map)['batchId'], nb.id);
    final r3 = rowsOf(units[2]);
    expect(r3.keys.toSet(), {'stockMovements'}, reason: 'into an existing batch: the batch row is not re-sent');
    expect(((r3['stockMovements'] as List).single as Map)['batchId'], oldBatch.id);

    final serials = await (adb.select(adb.productSerials)..where((s) => s.productId.equals(p.id))).get();
    expect(serials.singleWhere((s) => s.id == old.id).status.name, 'sold', reason: 'sold IMEI untouched');
    expect(serials.singleWhere((s) => s.id == old.id).updatedAt.toUtc(), t0);
    final batches = await c.read(productRepositoryProvider).watchBatches(p.id).first;
    expect({for (final b in batches) b.batchNo: b.qtyMilli}, {'OLD': Qty.units(4), 'R3NEW': Qty.units(6)},
        reason: 'batch stock = SUM of its movements');
    final all = await adb.select(adb.stockMovements).get();
    expect(all.where((m) => m.productId == p.id).fold<int>(0, (a, m) => a + m.qtyMilli), Qty.units(12),
        reason: 'product stock = batch stock (3 + 1 + 6) + 2 IMEIs');
  });

  test('TC-PROD-NEW-9/10 Drift: the edit form\'s update() = ONE upsertProduct unit: product (lowAlert 0) + ONLY the new '
      'IMEI / batch / variant rows + one "+N" movement for the IMEIs; nothing deleted', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final tid = shop.tenantId;
    final p = Product(id: newId(), tenantId: tid, name: 'QA R3 E', cost: 1, price: 2, category: 'x', tint: 0,
        initial: 'E', createdAt: t0, updatedAt: t0, lowAlertMilli: 5000);
    final oldS = ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: '910000000000001',
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
    final oldB = ProductBatch(id: newId(), tenantId: tid, productId: p.id, batchNo: 'OB', qtyMilli: 0, createdAt: t0, updatedAt: t0);
    final oldV = ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: 'M', color: 'အနက်', createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, serials: [oldS], batches: [oldB], variants: [oldV], initialStock: [
      restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(1)),
    ]);
    await adb.delete(adb.outbox).go();

    final t = nowUtc();
    await c.read(productServiceProvider).update(
      p.copyWith(lowAlertMilli: 0),
      serials: [
        for (final s in ['910000000000002', '910000000000003'])
          ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: s, status: SerialStatus.inStock, createdAt: t, updatedAt: t),
      ],
      batches: [ProductBatch(id: newId(), tenantId: tid, productId: p.id, batchNo: 'NB', qtyMilli: 0,
          expiryDate: DateTime.utc(2028, 2, 29), createdAt: t, updatedAt: t)],
      variants: [ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: 'XL', color: 'အနီ', createdAt: t, updatedAt: t)],
    );

    final units = await outbox(adb);
    expect(units.map((u) => u.kind), ['upsertProduct'], reason: 'ONE unit');
    final r = rowsOf(units.single);
    expect(((r['products'] as List).single as Map)['lowAlertMilli'], 0, reason: 'cleared alert = 0 on the wire');
    expect((r['productSerials'] as List).map((s) => (s as Map)['serial']).toSet(), {'910000000000002', '910000000000003'},
        reason: 'only the new IMEIs');
    expect((r['productBatches'] as List).map((b) => ((b as Map)['batchNo'], b['expiryDate'])).toList(), [('NB', '2028-02-29')]);
    expect((r['productVariants'] as List).map((v) => (v as Map)['size']).toList(), ['XL']);
    final mv = (r['stockMovements'] as List).single as Map;
    expect((mv['type'], mv['qtyMilli'], mv['batchId'], mv['variantId']), ('restock', 2000, null, null));

    expect(await adb.select(adb.productSerials).get(), hasLength(3));
    expect(await adb.select(adb.productBatches).get(), hasLength(2));
    expect(await adb.select(adb.productVariants).get(), hasLength(2));
    for (final row in [
      ...await adb.select(adb.productSerials).get().then((l) => l.where((x) => x.id == oldS.id).map((x) => (x.updatedAt, x.deletedAt))),
      ...await adb.select(adb.productBatches).get().then((l) => l.where((x) => x.id == oldB.id).map((x) => (x.updatedAt, x.deletedAt))),
      ...await adb.select(adb.productVariants).get().then((l) => l.where((x) => x.id == oldV.id).map((x) => (x.updatedAt, x.deletedAt))),
    ]) {
      expect((row.$1.toUtc(), row.$2), (t0, null), reason: 'existing module rows unchanged, not deleted');
    }
  });

  test('TC-POS-NEW-5 Drift: after the local-database round trip a batch expiring today is NOT expired, yesterday\'s is '
      '(phone time zone ${DateTime.now().timeZoneName})', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R3 X', cost: 1, price: 2, category: 'x', tint: 0,
        initial: 'X', createdAt: t0, updatedAt: t0);
    ProductBatch b(String no, DateTime e) => ProductBatch(id: newId(), tenantId: shop.tenantId, productId: p.id, batchNo: no,
        qtyMilli: 0, expiryDate: e, createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, batches: [
      b('TODAY', today),
      b('YDAY', today.subtract(const Duration(days: 1))),
      b('TOMORROW', today.add(const Duration(days: 1))),
    ]);
    final read = await c.read(productRepositoryProvider).watchBatches(p.id).first;
    expect({for (final x in read) x.batchNo: x.isExpired(now)}, {'TODAY': false, 'YDAY': true, 'TOMORROW': false});
  });
}
