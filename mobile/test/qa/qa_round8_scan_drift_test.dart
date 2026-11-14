// QA round 8 — IMEI scan at POS and duplicate barcode on the REAL local database (in-memory Drift), not the fake repos:
// the POS lookup reads `watchSerialRows` (drift_product_repository.dart: serial = code AND deletedAt IS NULL) and the
// live product list.
//
// Owner decision (c), 2026-11-14: "a scanned in-stock IMEI adds that phone with that IMEI (no IMEI question); only if
// neither a barcode nor an in-stock IMEI matches is 'ပစ္စည်းအသစ်' offered". limits.json productSerials.serial:
// myanmarDigitsToAscii. Trade-in decision (2b74d73): a sold IMEI received again = a NEW inStock row, history kept.
// Decision (a)/(b): duplicate barcode warns on save and asks at POS.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import '../sync_screens_test.dart' show drive, settle;

class _QaScanner implements BarcodeScanner {
  String? next;
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async => next;
}

const _unknownTitle = 'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  Future<(ProviderContainer, TestShop, AppDatabase, _QaScanner)> boot(WidgetTester tester, String template) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network()); // offline: units stay in the outbox
    }
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scanner = _QaScanner();
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          barcodeScannerProvider.overrideWithValue(scanner),
          initialLimitsProvider.overrideWithValue(bundledLimits()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    c.read(shopTemplateProvider.notifier).select(template);
    await settle(tester);
    return (c, shop, adb, scanner);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  }

  Future<void> openPos(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await settle(tester);
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await settle(tester);
    }
  }

  Future<void> burst(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
  }

  List<CartLine> cart(ProviderContainer c) => c.read(cartProvider).lines;

  testWidgets('TC-POS-NEW-13 Drift: in-stock IMEI → that phone + that IMEI; Myanmar digits; again → message; sold IMEI, '
      'deleted product\'s IMEI → "ပစ္စည်းအသစ်" sheet; trade-in → the NEW row; checkout sells exactly the scanned rows; '
      'a sold IMEI scanned again → sheet', (tester) async {
    final (c, shop, adb, scanner) = await boot(tester, 'phone');
    final tid = shop.tenantId;
    Product phone(String name, {String? barcode}) => Product(id: newId(), tenantId: tid, name: name, cost: 400000,
        price: 450000, category: 'ဖုန်း', barcode: barcode, tint: 0xFFDBEAFE, initial: 'P', createdAt: t0, updatedAt: t0);
    ProductSerial row(Product p, String imei, [SerialStatus st = SerialStatus.inStock]) => ProductSerial(
        id: newId(), tenantId: tid, productId: p.id, serial: imei, status: st, createdAt: t0, updatedAt: t0);
    const a = '359810000000001', b = '359810000000002', d = '359810000000004', tr = '359810000000005';
    final p = phone('QA R8 D phone', barcode: '6901443008800');
    final q = phone('QA R8 D gone');
    final rowA = row(p, a), rowB = row(p, b);
    final rowT = row(p, tr);
    // drive (fake zone), not runAsync: checkout / receive nudge the sync engine (sync_screens_test.dart `drive`).
    await drive(tester, () async {
      await c.read(productServiceProvider).create(p, serials: [rowA, rowB, rowT], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(3)),
      ]);
      await c.read(productServiceProvider).create(q, serials: [row(q, d)], initialStock: [
        restockMovement(tenantId: tid, productId: q.id, qtyMilli: Qty.units(1)),
      ]);
      // trade-in: tr sold, then received again (new inStock row)
      await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
        (productId: p.id, variantId: null, batchId: null, serialId: rowT.id, name: p.name, qtyMilli: 1000, price: 450000,
            cost: 400000),
      ], method: PaymentMethod.cash));
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [tr]);
      // q deleted on another phone (pulled): its serial row stays inStock
      await (adb.update(adb.products)..where((x) => x.id.equals(q.id)))
          .write(ProductsCompanion(deletedAt: Value(DateTime.utc(2026, 11, 1))));
    });
    final freshT = (await tester.runAsync(() => (adb.select(adb.productSerials)
          ..where((s) => s.serial.equals(tr) & s.id.equals(rowT.id).not()))
        .getSingle()))!;
    expect(freshT.status, SerialStatus.inStock);
    await openPos(tester, c);

    await burst(tester, a);
    expect(find.text('ဘယ် IMEI လဲ?'), findsNothing, reason: '(c) no IMEI question');
    expect(cart(c).map((l) => (l.productId, l.serialId)), [(p.id, rowA.id)]);

    scanner.next = ' ၃၅၉၈၁၀၀၀၀၀၀၀၀၀၂ ';
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await settle(tester);
    expect(cart(c).map((l) => (l.productId, l.serialId)), [(p.id, rowA.id), (p.id, rowB.id)],
        reason: 'Myanmar digits normalized like the server (productSerials.serial)');

    await burst(tester, a);
    expect(cart(c), hasLength(2), reason: 'IMEI already in the cart');
    expect(find.text('ဒီ IMEI ကို ထည့်ပြီးသားပါ။'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    await burst(tester, d);
    expect(find.text(_unknownTitle), findsOneWidget, reason: 'deleted product: its IMEI is not sold');
    await tester.tap(find.text('မလုပ်တော့ပါ'));
    await settle(tester);
    expect(cart(c), hasLength(2));

    await burst(tester, tr);
    expect(cart(c).last.serialId, freshT.id, reason: 'trade-in: the NEW in-stock row, never the old sold one');
    expect(cart(c), hasLength(3));

    // checkout through the screen
    await tester.runAsync(() => adb.delete(adb.outbox).go());
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
    final rows = (await tester.runAsync(() => adb.select(adb.productSerials).get()))!;
    String st(String id) => rows.singleWhere((r) => r.id == id).status.name;
    expect([st(rowA.id), st(rowB.id), st(rowT.id), st(freshT.id)], ['sold', 'sold', 'sold', 'sold']);
    final units = (await tester.runAsync(() => outbox(adb)))!;
    expect(units.map((u) => u.kind), ['checkout']);
    final sent = ((rowsOf(units.single)[WireTable.productSerials] as List?) ?? const []).cast<Map>();
    expect(sent.map((s) => '${s['id']}:${s['status']}').toSet(), {'${rowA.id}:sold', '${rowB.id}:sold', '${freshT.id}:sold'},
        reason: 'the checkout unit carries exactly the three scanned rows as sold');

    await openPos(tester, c);
    await burst(tester, a);
    expect(find.text(_unknownTitle), findsOneWidget, reason: 'sold IMEI → "ပစ္စည်းအသစ်" offered (decision c)');
    expect(cart(c), isEmpty);
    await tester.tap(find.text('မလုပ်တော့ပါ'));
    await settle(tester);
    await finish(tester);
  });

  testWidgets('TC-PROD-NEW-35 Drift: duplicate barcode → warning, "ဒီအတိုင်း သိမ်းမယ်" → ONE upsertProduct unit with the '
      'barcode; POS picker on the real database', (tester) async {
    final (c, shop, adb, _) = await boot(tester, 'grocery');
    final first = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R8 D first', cost: 1, price: 700, category: 'x',
        barcode: '8850000008900', tint: 0, initial: 'F', createdAt: t0, updatedAt: t0);
    await tester.runAsync(() => c.read(productServiceProvider).create(first));
    await tester.runAsync(() => adb.delete(adb.outbox).go());
    c.read(appRouterProvider).go(Routes.addProduct);
    await settle(tester);
    Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
    await tester.enterText(field('productName'), 'QA R8 D second');
    await tester.enterText(field('price'), '900');
    await tester.enterText(field('barcode'), '8850000008900');
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await settle(tester);
    expect(find.text('ဒီ Barcode ရှိပြီးသားပါ'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeSave')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);
    final units = (await tester.runAsync(() => outbox(adb)))!;
    expect(units.map((u) => u.kind), ['upsertProduct']);
    final prod = (rowsOf(units.single)[WireTable.products] as List).cast<Map>().single;
    expect((prod['name'], prod['barcode']), ('QA R8 D second', '8850000008900'));

    await openPos(tester, c);
    await burst(tester, '8850000008900');
    expect(find.text('ဘယ်ပစ္စည်းလဲ?'), findsOneWidget);
    expect(cart(c), isEmpty);
    await tester.tap(find.byKey(ValueKey('barcodeMatch-${first.id}')));
    await settle(tester);
    expect(cart(c).single.productId, first.id);
    await finish(tester);
  });
}
