// QA round 10 — fb3fd12 (BUG-28), adversarial, on the real POS screen: fake repos first, then the real local database.
//
// Owner, 2026-11-14 (hand-over): "the in-cart IMEI check covers every cart line, whichever product was picked."
// Both by scan and by tap; trade-in rows (a sold row + a newer in-stock row with the same IMEI); Drift and fake repos.
// Fix under test: module_pick_sheet.dart `cartSerialNumbers` — the IMEI picker leaves out every IMEI NUMBER already in
// the cart. Not over-excluding is checked too: a cleared cart offers the IMEI again.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import '../sync_screens_test.dart' show drive, settle;

const _picker = 'ဘယ် IMEI လဲ?';
const _inCart = 'ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ';
const _none = 'ရောင်းစရာ IMEI မကျန်တော့ပါ';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  Future<ProviderContainer> bootFake(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select('phone');
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  Product phone(String tid, String name) => Product(id: newId(), tenantId: tid, name: name, cost: 400000, price: 450000,
      category: 'ဖုန်း', tint: 0xFFDBEAFE, initial: 'P', createdAt: t0, updatedAt: t0);
  ProductSerial row(Product p, String imei, {SerialStatus status = SerialStatus.inStock, DateTime? at}) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: status, createdAt: at ?? t0,
      updatedAt: at ?? t0);
  Future<void> create(ProviderContainer c, Product p, List<ProductSerial> rows) => c.read(productServiceProvider).create(p,
      serials: rows,
      initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(
            rows.where((r) => r.status == SerialStatus.inStock).length)),
      ]);
  List<CartLine> cart(ProviderContainer c) => c.read(cartProvider).lines;

  Future<void> openPos(WidgetTester tester, ProviderContainer c, {bool drift = false}) async {
    c.read(appRouterProvider).go(Routes.pos);
    drift ? await settle(tester) : await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      drift ? await settle(tester) : await tester.pumpAndSettle();
    }
  }

  Future<void> tapProduct(WidgetTester tester, String name, {bool drift = false}) async {
    await tester.tap(find.text(name).first);
    drift ? await settle(tester) : await tester.pumpAndSettle();
  }

  Future<void> burst(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  String dump(ProviderContainer c) => '${cart(c).map((l) => l.name).toList()}';

  group('TC-POS-NEW-17 BUG-28 (fake repos): an IMEI number in the cart is never offered again, by tap or by scan', () {
    testWidgets('TAP then TAP: X picked on product A → product B lists only its other IMEI; tap A again → X not offered '
        '("ရောင်းစရာ IMEI မကျန်တော့ပါ"); cart cleared → X offered again on B (no over-exclusion)', (tester) async {
      final c = await bootFake(tester);
      final tid = c.read(tenantIdProvider);
      const x = '359901000000001', y = '359901000000002';
      final a = phone(tid, 'QA R10 tap A'), b = phone(tid, 'QA R10 tap B');
      final ax = row(a, x);
      await create(c, a, [ax]);
      await create(c, b, [row(b, x), row(b, y)]);
      await openPos(tester, c);

      await tapProduct(tester, a.name);
      expect(find.text(_picker), findsOneWidget);
      await tester.tap(inSheet(find.text(x)));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => l.serialId), [ax.id]);

      await tapProduct(tester, b.name);
      expect(find.text(_picker), findsOneWidget);
      expect(inSheet(find.text(x)), findsNothing, reason: 'X is in the cart from product A: ${dump(c)}');
      expect(inSheet(find.text(y)), findsOneWidget);
      await tester.tap(inSheet(find.text(y)));
      await tester.pumpAndSettle();
      expect(cart(c), hasLength(2));

      await tapProduct(tester, a.name);
      expect(inSheet(find.text(x)), findsNothing);
      expect(inSheet(find.text(_none)), findsOneWidget, reason: 'A has no other in-stock IMEI');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(cart(c), hasLength(2), reason: 'nothing added: ${dump(c)}');

      c.read(cartProvider.notifier).clear();
      await tester.pumpAndSettle();
      await tapProduct(tester, b.name);
      expect(inSheet(find.text(x)), findsOneWidget, reason: 'an empty cart must offer X again');
    });

    testWidgets('trade-in rows: A has X sold (old) + X in stock (received again), B has X in stock (duplicateSerial). Tap B, '
        'pick X → tap A: X not offered, the sold row never listed; scan X → the in-cart message; one phone line',
        (tester) async {
      final c = await bootFake(tester);
      final tid = c.read(tenantIdProvider);
      const x = '359901000000011';
      final a = phone(tid, 'QA R10 trade A'), b = phone(tid, 'QA R10 trade B');
      await create(c, a, [row(a, x, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 2)), row(a, x, at: DateTime.utc(2026, 10, 9))]);
      final bx = row(b, x, at: DateTime.utc(2026, 10, 5));
      await create(c, b, [bx]);
      await openPos(tester, c);

      await tapProduct(tester, b.name);
      await tester.tap(inSheet(find.text(x)));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => l.serialId), [bx.id]);

      await tapProduct(tester, a.name);
      expect(find.text(_picker), findsOneWidget);
      expect(inSheet(find.text(x)), findsNothing, reason: 'neither the in-stock trade-in row nor the sold row: ${dump(c)}');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await burst(tester, x);
      expect(find.text(_inCart), findsOneWidget);
      expect(cart(c).where((l) => l.serialId != null), hasLength(1), reason: dump(c));
    });
  });

  testWidgets('TC-POS-NEW-17 BUG-28 Drift: rows written by the app\'s services (A sold X, took it back with "Stock '
      'ဖြည့်မယ်"; B received X too). Scan X → tap the other product: X not offered; tap → tap the other way round too',
      (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network());
    }
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          initialLimitsProvider.overrideWithValue(bundledLimits()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    c.read(shopTemplateProvider.notifier).select('phone');
    await settle(tester);

    const x = '359901000000021', z = '359901000000022';
    final a = phone(shop.tenantId, 'QA R10 D A'), b = phone(shop.tenantId, 'QA R10 D B');
    final first = row(a, x);
    await drive(tester, () async {
      await create(c, a, [first]);
      await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
        (productId: a.id, variantId: null, batchId: null, serialId: first.id, name: a.name, qtyMilli: 1000, price: 450000,
            cost: 400000),
      ], method: PaymentMethod.cash));
      await c.read(stockServiceProvider).receive(productId: a.id, qtyMilli: Qty.units(1), serials: [x]); // trade-in
      await c.read(productServiceProvider).create(b);
      await c.read(stockServiceProvider).receive(productId: b.id, qtyMilli: Qty.units(2), serials: [x, z]); // duplicate
    });
    final rows = (await tester.runAsync(() => c.read(productRepositoryProvider).watchSerialRows(x).first))!;
    expect(rows.map((r) => (r.productId == a.id ? 'A' : 'B', r.status.name)).toList()..sort((p, q) => '$p'.compareTo('$q')),
        [('A', 'inStock'), ('A', 'sold'), ('B', 'inStock')], reason: 'setup: the flagged duplicateSerial state');

    await openPos(tester, c, drift: true);
    await burst(tester, x);
    await settle(tester);
    expect(cart(c), hasLength(1));
    final scannedFrom = cart(c).single.productId;
    final other = scannedFrom == a.id ? b : a;
    await tapProduct(tester, other.name, drift: true);
    expect(find.text(_picker), findsOneWidget);
    expect(inSheet(find.text(x)), findsNothing, reason: 'scan → tap: ${dump(c)}');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(cart(c), hasLength(1));

    c.read(cartProvider.notifier).clear();
    await settle(tester);
    await tapProduct(tester, b.name, drift: true);
    await tester.tap(inSheet(find.text(x)));
    await settle(tester);
    await tapProduct(tester, a.name, drift: true);
    expect(find.text(_picker), findsOneWidget);
    expect(inSheet(find.text(x)), findsNothing, reason: 'tap → tap: ${dump(c)}');
    expect(inSheet(find.text(_none)), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(cart(c).where((l) => l.serialId != null), hasLength(1), reason: dump(c));

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  });
}
