// QA round 12 — check of the new Known-limitation bullet (ee662f3) against the real local database and SyncEngine (fake HTTP):
//   "Two phones voiding the same sale while one is offline: the offline phone shows the stock returned twice (e.g. 1 sold,
//    voided on both → +2 instead of +1) until its next sync. The server applies the void once, and after the sync the phone
//    takes the server's copy and shows the right stock (TC-SYNC-NEW-23)."
// The phone's automatic triggers (sync_lifecycle.dart: back online, the timer) call syncNow() WITHOUT manual, so a phone
// whose pushes failed while offline is still in its push back-off (5 s … 10 min) when it comes back: that cycle only pulls.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
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

import '../drift_helpers.dart';
import '../fake_sync_api.dart';

String _c(int n) => n.toRadixString(16).padLeft(16, '0');

void main() {
  test('TC-SYNC-NEW-28 known limitation "two phones void one sale, one offline" (1 sold of 5): while A is offline its '
      'stock is right (5); back online inside its push back-off the automatic sync only pulls B\'s return → 6 (returned '
      'twice) and today 0; the double stays for automatic syncs until the back-off ends; then A\'s void is "skipped" → 5, '
      'one return, outbox empty', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final api = FakeSyncApi();
    var now = DateTime.now().toUtc();
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => now);
    addTearDown(engine.dispose);
    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r12 soap', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(1), price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    api.pages.add(page({}, cursor: _c(10)));
    await engine.syncNow(manual: true);
    Future<int> stock() async => (await (db.select(db.stockMovements)..where((m) => m.productId.equals(p.id))).get())
        .fold<int>(0, (a, m) => a + m.qtyMilli);
    Future<int> todaySales() async =>
        (await c.read(reportRepositoryProvider).watchReport(ReportPeriod.today).first).summary.sales;
    expect((await stock(), await todaySales()), (Qty.units(4), 150));

    // ---- A goes offline and voids; its automatic syncs fail (4 failures → 10 min back-off)
    final pullsBefore = api.pullCursors.length;
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    var lastFailure = now;
    for (var i = 0; i < 4; i++) {
      api.pushErrors.add(const ApiError.network());
      lastFailure = now;
      await engine.syncNow();
      now = engine.pushAfter!.add(const Duration(milliseconds: 1)); // the next automatic attempt is allowed
    }
    expect(engine.pushAfter, lastFailure.add(SyncEngine.backoffFor(4)), reason: '4 failures → 10 min back-off');
    now = lastFailure.add(const Duration(seconds: 30)); // back online 30 s after the last failed attempt
    expect(api.pullCursors.length, pullsBefore, reason: 'offline: a failed push stops the cycle, no pull');
    final offline = await stock();

    // ---- meanwhile B voided the same sale and synced: the server has B's void and B's return
    final mine = (await (db.select(db.stockMovements)..where((m) => m.saleId.equals(sale.id) & m.qtyMilli.isBiggerThanValue(0)))
        .get()).single;
    final serverPage = page({
      'sales': [{...saleWire(await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle()),
        'voidedAt': DateTime.utc(2026, 11, 15, 1).toIso8601String(), 'deviceId': 'phone-b'}],
      'stockMovements': [{...movementWire(mine), 'id': newId(), 'deviceId': 'phone-b'}],
    }, cursor: _c(20));

    // ---- A back online: the connectivity trigger = syncNow() without manual, inside the back-off
    api.pages.add(serverPage);
    final pushesBefore = api.pushes.length;
    await engine.syncNow();
    expect(api.pushes.length, pushesBefore, reason: 'inside the back-off: no push');
    final backOnline = await stock();
    final todayBackOnline = await todaySales();
    // a later timer tick, 9 minutes on, still inside the 10-minute back-off
    now = now.add(const Duration(minutes: 9));
    await engine.syncNow();
    final nineMinutes = await stock();

    // ---- the back-off ends: the push goes out, the server says "skipped" (already voided by B), rewind, re-pull
    now = now.add(const Duration(minutes: 2));
    api.outcome = (u) => u.kind == 'voidSale' ? UnitOutcome.skipped : UnitOutcome.applied;
    api.pages.add(serverPage);
    await engine.syncNow();
    final after = await stock();
    final returns = (await (db.select(db.stockMovements)..where((m) => m.saleId.equals(sale.id) & m.qtyMilli.isBiggerThanValue(0)))
        .get()).length;
    // ignore: avoid_print
    print('TC-SYNC-NEW-28 stock: before void 4, offline ${Qty.format(offline)}, back online ${Qty.format(backOnline)} '
        '(today $todayBackOnline), +9 min ${Qty.format(nineMinutes)}, after the back-off ${Qty.format(after)} '
        '(returns: $returns)');
    expect(
        (offline, backOnline, todayBackOnline, nineMinutes, after, returns),
        (Qty.units(5), Qty.units(6), 0, Qty.units(6), Qty.units(5), 1));
    expect(await db.select(db.outbox).get(), isEmpty);
  });
}
