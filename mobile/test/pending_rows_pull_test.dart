import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/reports/data/report_repository.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';

/// BUG-32, general rule: a pull never overwrites a row that is part of an unsent or blocked outbox unit
/// (any table). Once that unit is accepted, the phone pulls again from before the skipped page, so it
/// gets the server's current copy of those rows.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('void fails to send → the next pull does not undo it; day totals stay correct; after the void is sent the '
      'phone pulls again and takes the server copy', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final api = FakeSyncApi()..pullErrors[0] = const ApiError.network();
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: nowUtc);
    addTearDown(engine.dispose);
    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'လက်ဖက်ရည်', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'လ', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(2), price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    final echo = jsonDecode(jsonEncode(saleWire(await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle())))
        as Map<String, dynamic>; // the server's copy: not voided
    Future<PeriodSummary> today() async => (await c.read(reportRepositoryProvider).watchReport(ReportPeriod.today).first).summary;

    await engine.syncNow(manual: true); // checkout applied; the pull fails
    expect(await db.select(db.outbox).get(), isEmpty);
    expect((await today()).sales, 300);

    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    api.pushErrors.add(const ApiError.network());
    await engine.syncNow(); // the void push fails → back-off
    api.pages.add(page({'sales': [echo]}, cursor: '0000000000000010'));
    await engine.syncNow(); // automatic, within the back-off: no push, the pull runs
    expect((await db.select(db.outbox).get()).map((o) => o.kind), ['voidSale']);
    final row = await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle();
    expect(row.voidedAt, isNotNull, reason: 'the pull must not undo an unsent void');
    expect((await today()).sales, 0, reason: 'the voided sale is not counted');
    expect(await db.readState(SyncStateKeys.pullCursor), '0000000000000010', reason: 'the page was taken (minus that row)');

    // The void is sent; the phone pulls again from before the skipped page and takes the server's voided copy.
    final voidedAt = DateTime.now().toUtc().toIso8601String();
    api.pages.add(page({'sales': [{...echo, 'voidedAt': voidedAt, 'updatedAt': voidedAt}]}, cursor: '0000000000000011'));
    await engine.syncNow(manual: true);
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(api.pullCursors.last, '0', reason: 'pulled again from the cursor before the skipped page');
    expect(await db.readState(SyncStateKeys.repullKeys), isNull);
    expect((await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle()).voidedAt, isNotNull);
    expect((await today()).sales, 0);
  });

  test('any table: a product with an unsent edit and a stock movement of an unsent restock are not overwritten', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'ဆီ', cost: 100, price: 150, category: 'x',
        barcode: '885', tint: 0, initial: 'ဆ', createdAt: t, updatedAt: t);
    final m = restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(3));
    await c.read(productServiceProvider).create(p, initialStock: [m]); // unsent
    final local = await (db.select(db.stockMovements)..where((x) => x.id.equals(m.id))).getSingle();
    await store.mergePage(page({
      'products': [productWire(await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle())
        ..['name'] = 'ဆီ (ဆာဗာ)'..['barcode'] = null..['updatedAt'] = '2030-01-01T00:00:00.000Z'],
      'stockMovements': [movementWire(local)..['qtyMilli'] = 1],
    }, cursor: '0000000000000020'));
    final row = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((row.name, row.barcode), ('ဆီ', '885'));
    expect((await (db.select(db.stockMovements)..where((x) => x.id.equals(m.id))).getSingle()).qtyMilli, Qty.units(3));
    final keys = (jsonDecode((await db.readState(SyncStateKeys.repullKeys))!) as List).toSet();
    expect(keys, {'products:${p.id}', 'stockMovements:${m.id}'});
    expect(await db.readState(SyncStateKeys.repullFrom), '0');
  });

  test('a blocked (rejected) unit keeps its rows protected; nothing is pulled again until it is fixed and sent', () async {
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'ဆပ်ပြာ', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'ဆ', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p);
    final unit = (await db.select(db.outbox).get()).single;
    await store.applyResults([unit], [UnitResult(unitId: unit.unitId, outcome: UnitOutcome.rejected, code: 'invalid')]);
    await store.mergePage(page({
      'products': [productWire(await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle())
        ..['name'] = 'other'..['updatedAt'] = '2030-01-01T00:00:00.000Z'],
    }, cursor: '0000000000000030'));
    expect((await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).name, 'ဆပ်ပြာ');
    await store.applyResults(const [], const []); // any later push result: still blocked → no rewind
    expect(await db.readState(SyncStateKeys.pullCursor), '0000000000000030');
    expect(await db.readState(SyncStateKeys.repullKeys), isNotNull);
  });
}
