import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_view.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// BUG-31: a field cleared on one phone is cleared on the others. Pulled rows are applied whole (NULLs
/// included) under the existing rules: last-writer-wins, never over an unpushed local edit.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  const tid = 't-31';
  final t1 = DateTime.utc(2026, 11, 14, 9), t2 = DateTime.utc(2026, 11, 14, 10);

  Map<String, dynamic> product(String id, DateTime at,
          {String? barcode, int? wholesale, int? expiryDays, String name = 'ဆပ်ပြာ'}) =>
      {
        'id': id, 'tenantId': tid, 'name': name, 'category': 'x', 'unit': 'ခု', 'cost': 100, 'price': 150,
        'barcode': barcode, 'wholesalePrice': wholesale, 'expiryAlertDays': expiryDays, 'warrantyMonths': null,
        'lowAlertMilli': 0, 'tint': -1, 'initial': 'Q',
        'createdAt': '2026-11-14T08:00:00Z', 'updatedAt': at.toIso8601String(), 'deletedAt': null,
      };
  Map<String, dynamic> customer(String id, DateTime at, {int? limit}) => {
        'id': id, 'tenantId': tid, 'name': 'မမ', 'phone': '0912345678', 'address': null, 'creditLimit': limit, 'note': null,
        'createdAt': '2026-11-14T08:00:00Z', 'updatedAt': at.toIso8601String(), 'deletedAt': null,
      };

  test('pull: a newer row with NULL barcode / wholesale price / expiry days / credit limit clears them here', () async {
    final store = SyncStore(db, tenantId: tid, deviceId: 'phone-a');
    final p = newId(), c = newId();
    await store.mergePage(page({
      'products': [product(p, t1, barcode: '8850000099101', wholesale: 140, expiryDays: 30)],
      'customers': [customer(c, t1, limit: 50000)],
    }, cursor: '01'));
    final before = await db.select(db.products).getSingle();
    expect((before.barcode, before.wholesalePrice, before.expiryAlertDays), ('8850000099101', 140, 30));

    await store.mergePage(page({
      'products': [product(p, t2)],
      'customers': [customer(c, t2)],
    }, cursor: '02'));
    final after = await db.select(db.products).getSingle();
    expect((after.barcode, after.wholesalePrice, after.expiryAlertDays, after.updatedAt), (null, null, null, t2));
    expect((await db.select(db.customers).getSingle()).creditLimit, isNull);
  });

  test('pull: an OLDER row with NULLs does not clear newer local values (last-writer-wins unchanged)', () async {
    final store = SyncStore(db, tenantId: tid, deviceId: 'phone-a');
    final p = newId();
    await store.mergePage(page({'products': [product(p, t2, barcode: '885', wholesale: 140)]}, cursor: '01'));
    await store.mergePage(page({'products': [product(p, t1)]}, cursor: '02'));
    final row = await db.select(db.products).getSingle();
    expect((row.barcode, row.wholesalePrice), ('885', 140));
  });

  test('pull never overwrites an unpushed local edit, NULLs included (pending-outbox rule unchanged)', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'ဆပ်ပြာ', cost: 100, price: 150, category: 'x',
        barcode: '8850000099102', wholesalePrice: 140, tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p); // in the outbox, not pushed
    await SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).mergePage(page({
      'products': [product(p.id, DateTime.utc(2030))..['tenantId'] = shop.tenantId],
    }, cursor: '01'));
    final row = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((row.barcode, row.wholesalePrice), ('8850000099102', 140));
  });

  test('push: clearing barcode / wholesale price / expiry days sends them as null (keys present)', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'ဆေး', cost: 100, price: 150, category: 'x',
        barcode: '8850000099103', wholesalePrice: 140, expiryAlertDays: 30, tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p);
    await c.read(productServiceProvider).update(
        p.copyWith(barcode: () => null, wholesalePrice: () => null, expiryAlertDays: () => null));
    final units = await (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();
    final sent = ((jsonDecode(units.last.rowsJson) as Map)['products'] as List).single as Map;
    for (final k in ['barcode', 'wholesalePrice', 'expiryAlertDays']) {
      expect(sent.containsKey(k), isTrue, reason: k);
      expect(sent[k], isNull, reason: k);
    }
    final row = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((row.barcode, row.wholesalePrice, row.expiryAlertDays), (null, null, null));
  });

  test('a duplicate barcode cleared on another phone is resolved here: the scan finds one product', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    final a = newId(), b = newId();
    Map<String, dynamic> mine(Map<String, dynamic> r) => r..['tenantId'] = shop.tenantId;
    await store.mergePage(page({
      'products': [mine(product(a, t1, barcode: '8850000099104', name: 'က')), mine(product(b, t1, barcode: '8850000099104', name: 'ခ'))],
    }, cursor: '01'));
    final limits = bundledLimits();
    Future<List<ProductView>> all() => settled(c, productsProvider);
    expect(productsByBarcode(await all(), '8850000099104', limits), hasLength(2));

    await store.mergePage(page({'products': [mine(product(b, t2, name: 'ခ'))]}, cursor: '02')); // B cleared it
    final left = productsByBarcode(await all(), '8850000099104', limits);
    expect(left.map((v) => v.id), [a]);
  });
}
