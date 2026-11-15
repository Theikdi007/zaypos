// QA round 9 — 0b3e2d4 (BUG-27 + the owner's "sold IMEI" message), adversarial, on the real POS screen with the fake repos.
// The same rules on the real local database: m/qa/qa_round9_scan_drift_test.dart.
//
// Owner, 2026-11-14 (quoted in the hand-over):
// - BUG-27: "when adding by IMEI scan, check the IMEI number against every line already in the cart. If it is already there,
//   show 'ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ' and don't add it again."
// - item 4: "POS scan of an IMEI whose last status is 'sold': show \"ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်'
//   ကနေ လက်ခံပါ\" instead of offering 'ပစ္စည်းအသစ်'."
// Developer's choices under test: "last status" = the row with the latest createdAt; a product barcode equal to the code
// still wins over the sold message; a deleted product's in-stock IMEI still goes to "ပစ္စည်းအသစ်". Known limitation
// (bugs.md): "Only in shops with IMEI tracking on."
// Commit message 0b3e2d4: "one box is never two phones (duplicateSerial)".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;

class _QaScanner implements BarcodeScanner {
  String? next;
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async => next;
}

const inCartMsg = 'ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ';
const soldMsg = "ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ";
const unknownTitle = 'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  Future<(ProviderContainer, _QaScanner)> boot(WidgetTester tester, {String template = 'phone'}) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scanner = _QaScanner();
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      barcodeScannerProvider.overrideWithValue(scanner),
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, scanner);
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  List<CartLine> cart(ProviderContainer c) => c.read(cartProvider).lines;

  Product phone(ProviderContainer c, String name, {String? barcode}) => Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400000, price: 450000, category: 'ဖုန်း',
        barcode: barcode, tint: 0xFFDBEAFE, initial: 'P', createdAt: t0, updatedAt: t0,
      );
  ProductSerial row(Product p, String imei, {SerialStatus status = SerialStatus.inStock, DateTime? at}) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: status, createdAt: at ?? t0,
      updatedAt: at ?? t0);
  Future<void> create(ProviderContainer c, Product p, List<ProductSerial> rows) => c.read(productServiceProvider).create(p,
      serials: rows,
      initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(
            rows.where((r) => r.status == SerialStatus.inStock).length)),
      ]);
  void delete(ProviderContainer c, Product p) {
    final i = db(c).products.indexWhere((x) => x.id == p.id);
    db(c).products[i] = p.copyWith(deletedAt: () => DateTime.utc(2026, 11, 1));
    db(c).touch({FakeTable.products});
  }

  Future<void> openPos(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> burst(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      final key = RegExp('[0-9a-z]').hasMatch(ch) ? LogicalKeyboardKey(ch.codeUnitAt(0)) : LogicalKeyboardKey.keyA;
      await tester.sendKeyEvent(key, character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> clearSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  // ================================================================ TC-POS-NEW-14 BUG-27: cart checked by the IMEI NUMBER
  group('TC-POS-NEW-14 BUG-27 IMEI already in the cart, by its number', () {
    testWidgets('the same IMEI on two products (duplicateSerial): picked by TAPPING product 1, then scanned (ASCII, then '
        'Myanmar digits by camera) → "ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ" each time, still ONE line', (tester) async {
      final (c, scanner) = await boot(tester);
      const imei = '359900000000101';
      final p1 = phone(c, 'QA R9 twin A'), p2 = phone(c, 'QA R9 twin B');
      final r1 = row(p1, imei);
      await create(c, p1, [r1]);
      await create(c, p2, [row(p2, imei)]);
      await openPos(tester, c);
      await tester.tap(find.text('QA R9 twin A').first);
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
      await tester.tap(inSheet(find.text(imei)));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => l.serialId), [r1.id]);

      await burst(tester, imei);
      expect(find.text(inCartMsg), findsOneWidget);
      expect(find.text(unknownTitle), findsNothing);
      expect(cart(c), hasLength(1), reason: 'BUG-27: twin row on product B must not be added');
      await clearSnack(tester);

      scanner.next = ' ၃၅၉၉၀၀၀၀၀၀၀၀၁၀၁ ';
      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      expect(find.text(inCartMsg), findsOneWidget, reason: 'Myanmar digits are the same IMEI');
      expect(cart(c), hasLength(1));
      await clearSnack(tester);
    });
  });

  // ================================================================ TC-POS-NEW-15 sold IMEI scanned at POS
  group('TC-POS-NEW-15 sold IMEI scanned at POS (owner item 4)', () {
    testWidgets('trade-in chain sold → received → sold again: the "sold" message, no "ပစ္စည်းအသစ်", nothing added; '
        'chain sold → received: the NEW in-stock row is added, no message', (tester) async {
      final (c, _) = await boot(tester);
      const again = '359900000000201', back = '359900000000202';
      final p = phone(c, 'QA R9 chain');
      final fresh = row(p, back, at: DateTime.utc(2026, 10, 20));
      await create(c, p, [
        row(p, again, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 2)),
        row(p, again, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 10)),
        row(p, back, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 3)),
        fresh,
      ]);
      await openPos(tester, c);
      await burst(tester, again);
      expect(find.text(soldMsg), findsOneWidget);
      expect(find.text(unknownTitle), findsNothing);
      expect(cart(c), isEmpty);
      await clearSnack(tester);

      await burst(tester, back);
      expect(find.text(soldMsg), findsNothing);
      expect(cart(c).map((l) => l.serialId), [fresh.id], reason: 'received again → sells the new row');
    });

    testWidgets('"last status" = the row with the LATEST createdAt, not the list order: [sold 10-20 on P, in stock 10-05 on '
        'deleted Q] → sold message; [in stock 10-20 on deleted Q, sold 10-05 on P] → "ပစ္စည်းအသစ်"', (tester) async {
      final (c, _) = await boot(tester);
      const x = '359900000000301', y = '359900000000302';
      final p = phone(c, 'QA R9 order P'), q = phone(c, 'QA R9 order Q');
      // insertion order is the opposite of createdAt order on purpose
      await create(c, q, [row(q, x, at: DateTime.utc(2026, 10, 5)), row(q, y, at: DateTime.utc(2026, 10, 20))]);
      await create(c, p, [
        row(p, x, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 20)),
        row(p, y, status: SerialStatus.sold, at: DateTime.utc(2026, 10, 5)),
      ]);
      delete(c, q);
      await openPos(tester, c);
      await burst(tester, x);
      expect(find.text(soldMsg), findsOneWidget);
      expect(find.text(unknownTitle), findsNothing);
      await clearSnack(tester);
      await burst(tester, y);
      expect(find.text(unknownTitle), findsOneWidget, reason: 'latest row is in stock (deleted product) → not "sold"');
      expect(find.text(soldMsg), findsNothing);
      expect(cart(c), isEmpty);
    });

    testWidgets('a product barcode equal to a sold IMEI wins (that product is added, no message); a deleted product\'s '
        'sold IMEI → the sold message; IMEI tracking OFF → "ပစ္စည်းအသစ်", never the sold message', (tester) async {
      final (c, _) = await boot(tester);
      const code = '359900000000401', gone = '359900000000402';
      final box = phone(c, 'QA R9 box', barcode: code);
      await c.read(productServiceProvider).create(box, initialStock: [
        restockMovement(tenantId: box.tenantId, productId: box.id, qtyMilli: Qty.units(3)),
      ]);
      final p = phone(c, 'QA R9 sold one'), dead = phone(c, 'QA R9 deleted');
      await create(c, p, [row(p, code, status: SerialStatus.sold)]);
      await create(c, dead, [row(dead, gone, status: SerialStatus.sold)]);
      delete(c, dead);
      await openPos(tester, c);

      await burst(tester, code);
      expect(find.text(soldMsg), findsNothing);
      expect(cart(c).map((l) => l.productId), [box.id], reason: 'developer choice: a product barcode wins');

      await burst(tester, gone);
      expect(find.text(soldMsg), findsOneWidget, reason: 'owner: last status sold → the sold message');
      expect(cart(c), hasLength(1));
      await clearSnack(tester);

      c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.serialWarranty, false);
      await tester.pumpAndSettle();
      await burst(tester, gone);
      expect(find.text(soldMsg), findsNothing, reason: 'bugs.md: only in shops with IMEI tracking on');
      expect(find.text(unknownTitle), findsOneWidget);
    });
  });

  // ================================================================ TC-POS-NEW-16 one box = one phone, by TAP after a scan
  group('TC-POS-NEW-16 duplicateSerial: IMEI scanned, then the twin product tapped', () {
    testWidgets('scan IMEI X (product A\'s row) → tap product B (also has X in stock) → the IMEI picker does not offer X '
        'again, or picking it adds nothing: ONE phone for one box', (tester) async {
      final (c, _) = await boot(tester);
      const imei = '359900000000501';
      final p1 = phone(c, 'QA R9 tap A'), p2 = phone(c, 'QA R9 tap B');
      await create(c, p1, [row(p1, imei)]);
      await create(c, p2, [row(p2, imei), row(p2, '359900000000502')]);
      await openPos(tester, c);
      await burst(tester, imei);
      expect(cart(c), hasLength(1));
      await tester.tap(find.text('QA R9 tap B').first);
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
      final offered = inSheet(find.text(imei));
      if (offered.evaluate().isNotEmpty) {
        await tester.tap(offered);
        await tester.pumpAndSettle();
      }
      expect(cart(c).where((l) => l.serialId != null).length, 1,
          reason: 'commit 0b3e2d4: "one box is never two phones (duplicateSerial)"; cart: '
              '${cart(c).map((l) => '${l.name} ${l.serialId}').toList()}');
    });
  });
}
