// QA round 6 — real local database (in-memory Drift) for BUG-22 and BUG-23 (667a0e2):
// - BUG-22: the real edit form on Drift → the pushed upsertProduct unit carries the product (expiryAlertDays 30), the
//   opening batch (with its expiry date) and the two "opening batch" adjustments; SQL stock per batch = product stock.
//   The printed wire shape is what b/ZayPOS.QA.Tests/QaRound6Tests.cs pushes to the server.
// - BUG-23: voiding the original sale after a trade-in → the voidSale unit does not send the old IMEI row back to
//   inStock and has no voidReturn for that line; the SQL in-stock set has the IMEI once; un-void writes no second −1.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show settle;
import 'qa_form_helpers.dart';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  testWidgets('TC-PROD-NEW-27 Drift: edit form switch to "ရက် ၃၀ အလို" with 10 loose → ONE upsertProduct unit = product '
      '(expiryAlertDays 30) + opening batch (expiry) + adjustments −10 loose / +10 into the batch; SQL batch stock 10, '
      'loose 0', (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network()); // offline: units stay in the outbox
    }
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    c.read(shopTemplateProvider.notifier).select('pharmacy');
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R6 D med', cost: 100, price: 150, category: 'x',
        tint: 0xFFDBEAFE, initial: 'D', createdAt: t0, updatedAt: t0);
    await tester.runAsync(() => c.read(productServiceProvider).create(p, initialStock: [
          restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(10), note: 'initial'),
        ]));
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    await tester.runAsync(() => adb.delete(adb.outbox).go());

    c.read(appRouterProvider).go(Routes.products);
    await settle(tester);
    await tester.enterText(find.byType(EditableText).first, p.name);
    await settle(tester);
    await tester.tap(find.text(p.name).last);
    await settle(tester);
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget);
    await pickExpiryWarn(tester, warn30Label);
    await settle(tester);
    expect(find.byKey(const ValueKey('openingBatchNote')), findsOneWidget, reason: 'Drift: loose stock 10 loaded');
    final f = find.descendant(of: find.byKey(const ValueKey('batchNo')), matching: find.byType(EditableText));
    await tester.ensureVisible(f);
    await tester.enterText(f, 'DOPEN');
    await pickAddProductExpiry(tester, 28);
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await settle(tester);
    await settle(tester);
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsNothing, reason: 'saved');

    final units = (await tester.runAsync(() => outbox(adb)))!;
    expect(units.map((u) => u.kind), ['upsertProduct'], reason: 'ONE unit');
    final rows = rowsOf(units.single);
    final prod = (rows[WireTable.products] as List).cast<Map>().single;
    final batches = (rows[WireTable.productBatches] as List).cast<Map>();
    final moves = (rows[WireTable.stockMovements] as List).cast<Map>();
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-28';
    expect(prod['expiryAlertDays'], 30);
    expect(batches.map((b) => (b['batchNo'], '${b['expiryDate']}'.substring(0, 10))), [('DOPEN', day)]);
    final bid = batches.single['id'];
    expect(moves.map((m) => (m['type'], m['qtyMilli'], m['batchId'], m['note'])).toSet(),
        {('adjustment', -10000, null, 'opening batch'), ('adjustment', 10000, bid, 'opening batch')});
    // ignore: avoid_print
    print('TC-PROD-NEW-27 wire: ${jsonEncode({'batches': batches, 'stockMovements': moves})}');

    final sql = (await tester.runAsync(() => (adb.select(adb.stockMovements)
          ..where((m) => m.productId.equals(p.id) & m.deletedAt.isNull()))
        .get()))!;
    int sum(bool Function(dynamic m) w) => sql.where(w).fold(0, (a, m) => a + m.qtyMilli);
    expect((sum((m) => m.batchId == bid), sum((m) => m.batchId == null), sum((_) => true)),
        (Qty.units(10), 0, Qty.units(10)));
    // let the app's debounced sync (offline → network error) run out before the test ends
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  });

  test('TC-PROD-NEW-28 Drift: void of the original sale after a trade-in → voidSale unit without the old IMEI row and '
      'without a voidReturn for the phone line; SQL in-stock set has the IMEI once; un-void → no −1 for the phone',
      () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final repo = c.read(productRepositoryProvider);
    const imei = '358000000000001';
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R6 D phone', cost: 1, price: 2, category: 'x',
        tint: 0, initial: 'D', createdAt: t0, updatedAt: t0);
    final old = ProductSerial(id: newId(), tenantId: shop.tenantId, productId: p.id, serial: imei,
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, serials: [old], initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(1)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: old.id, name: p.name, qtyMilli: 1000, price: 2, cost: 1),
    ], method: PaymentMethod.cash));
    await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [imei]);
    Future<int> stock() async => (await (adb.select(adb.stockMovements)
              ..where((m) => m.productId.equals(p.id) & m.deletedAt.isNull()))
            .get())
        .fold<int>(0, (a, m) => a + m.qtyMilli);

    await adb.delete(adb.outbox).go();
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    final v = await outbox(adb);
    expect(v.map((u) => u.kind), ['voidSale']);
    final vr = rowsOf(v.single);
    final serials = ((vr[WireTable.productSerials] as List?) ?? const []).cast<Map>();
    final moves = ((vr[WireTable.stockMovements] as List?) ?? const []).cast<Map>();
    expect(serials.where((s) => s['id'] == old.id && s['status'] == 'inStock'), isEmpty,
        reason: 'the old row is not sent back to inStock');
    expect(moves.where((m) => m['productId'] == p.id), isEmpty, reason: 'no voidReturn for the traded-in line');
    expect((vr[WireTable.sales] as List).cast<Map>().single['voidedAt'], isNotNull, reason: 'the sale itself is voided');
    expect(await repo.watchInStockSerialValues().first, {imei});
    final rowsX = await (adb.select(adb.productSerials)..where((s) => s.serial.equals(imei))).get();
    expect(rowsX.where((s) => s.status.name == 'inStock'), hasLength(1));
    expect(rowsX.singleWhere((s) => s.id == old.id).status.name, 'sold');
    expect(await stock(), Qty.units(1));

    await adb.delete(adb.outbox).go();
    await c.read(voidSaleServiceProvider).setVoided(sale.id, false);
    final u = rowsOf((await outbox(adb)).single);
    expect(((u[WireTable.stockMovements] as List?) ?? const []).cast<Map>().where((m) => m['productId'] == p.id), isEmpty,
        reason: 'un-void: no second −1');
    expect(await stock(), Qty.units(1));
    expect(await repo.watchInStockSerialValues().first, {imei});
  });
}
