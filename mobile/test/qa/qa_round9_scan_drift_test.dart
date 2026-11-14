// QA round 9 — 0b3e2d4 on the REAL local database (in-memory Drift): the sold-IMEI message and the cart check by IMEI
// number, with rows written by the app's own services (checkout, "Stock ဖြည့်မယ်" receive), not hand-made rows.
// drift_product_repository.dart watchSerialRows: serial = code AND deletedAt IS NULL, ordered by createdAt.
//
// Owner, 2026-11-14: "POS scan of an IMEI whose last status is 'sold': show \"ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင်
// 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ\" instead of offering 'ပစ္စည်းအသစ်'." Trade-in decision (2b74d73): a sold IMEI received again =
// a NEW inStock row, history kept. limits.json productSerials.serial: myanmarDigitsToAscii.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
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

const _inCart = 'ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ';
const _sold = "ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ";
const _unknownTitle = 'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  testWidgets('TC-POS-NEW-15 Drift: trade-in chain through the app\'s services — sold → scan: sold message; received again '
      '→ scan: the new row; sold again → Myanmar-digit scan: sold message; received a 2nd time → scan: the newest row, '
      'scan again: in-cart message; a product barcode equal to a sold IMEI wins', (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network());
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
    c.read(shopTemplateProvider.notifier).select('phone');
    await settle(tester);

    final tid = shop.tenantId;
    const x = '359910000000001', boxCode = '359910000000009';
    Product phone(String name, {String? barcode}) => Product(id: newId(), tenantId: tid, name: name, cost: 400000,
        price: 450000, category: 'ဖုန်း', barcode: barcode, tint: 0xFFDBEAFE, initial: 'P', createdAt: t0, updatedAt: t0);
    final p = phone('QA R9 D chain');
    final box = phone('QA R9 D box', barcode: boxCode);
    final first = ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: x, status: SerialStatus.inStock,
        createdAt: t0, updatedAt: t0);
    final boxRow = ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: boxCode,
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
    Future<void> sell(String serialId) => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: serialId, name: p.name, qtyMilli: 1000, price: 450000,
              cost: 400000),
        ], method: PaymentMethod.cash));
    Future<List<ProductSerial>> rowsOfX() async =>
        (await tester.runAsync(() => c.read(productRepositoryProvider).watchSerialRows(x).first))!;
    Future<void> openPos() async {
      c.read(cartProvider.notifier).clear();
      c.read(appRouterProvider).go(Routes.pos);
      await settle(tester);
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
        await tester.tap(find.text('ပစ္စည်းများ'));
        await settle(tester);
      }
    }

    Future<void> burst(String s) async {
      for (final ch in s.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
    }

    Future<void> clearSnack() async {
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
    }

    List<CartLine> cart() => c.read(cartProvider).lines;

    await drive(tester, () async {
      await c.read(productServiceProvider).create(p, serials: [first, boxRow], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(2)),
      ]);
      await c.read(productServiceProvider).create(box, initialStock: [
        restockMovement(tenantId: tid, productId: box.id, qtyMilli: Qty.units(2)),
      ]);
      await sell(first.id);
      await sell(boxRow.id);
    });

    // 1. sold once
    await openPos();
    await burst(x);
    expect(find.text(_sold), findsOneWidget);
    expect(find.text(_unknownTitle), findsNothing);
    expect(cart(), isEmpty);
    await clearSnack();

    // 2. received again with "Stock ဖြည့်မယ်" (the service behind the sheet) → the new row is sold by a scan
    await drive(tester, () => c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [x]));
    final second = (await rowsOfX()).singleWhere((r) => r.status == SerialStatus.inStock);
    await openPos();
    await burst(x);
    expect(find.text(_sold), findsNothing);
    expect(cart().map((l) => l.serialId), [second.id]);

    // 3. sold again (through the service) → Myanmar-digit camera scan → sold message
    await drive(tester, () => sell(second.id));
    expect((await rowsOfX()).map((r) => r.status), everyElement(SerialStatus.sold));
    await openPos();
    scanner.next = ' ၃၅၉၉၁၀၀၀၀၀၀၀၀၀၁ ';
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await settle(tester);
    expect(find.text(_sold), findsOneWidget, reason: 'two sold rows, the latest is sold');
    expect(cart(), isEmpty);
    await clearSnack();

    // 4. received a 2nd time → the newest row; scanning again → in-cart message
    await drive(tester, () => c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [x]));
    final rows = await rowsOfX();
    expect(rows, hasLength(3), reason: 'history kept: two sold rows + one new');
    final third = rows.singleWhere((r) => r.status == SerialStatus.inStock);
    await openPos();
    await burst(x);
    expect(cart().map((l) => l.serialId), [third.id]);
    await burst(x);
    expect(find.text(_inCart), findsOneWidget);
    expect(cart(), hasLength(1));
    await clearSnack();

    // 5. a product barcode equal to a sold IMEI: the product wins
    await openPos();
    await burst(boxCode);
    expect(find.text(_sold), findsNothing);
    expect(cart().map((l) => l.productId), [box.id]);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  });
}
