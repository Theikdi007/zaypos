// QA round 8 — scan lookup (beta-polish e0ea12b), adversarial edge cases on the real screens with the fake repositories.
// The IMEI lookup is re-checked on the real local database in m/qa/qa_round8_scan_drift_test.dart.
//
// Owner decisions (2026-11-14, quoted in the hand-over):
// (a) "duplicate barcode → Add/Edit Product warns (not blocks) when saving a new/changed barcode already on another live
//     product";
// (b) "a POS scan matching several products opens a picker instead of auto-picking";
// (c) "phone shops: a scanned in-stock IMEI adds that phone with that IMEI (no IMEI question); only if neither a barcode
//     nor an in-stock IMEI matches is 'ပစ္စည်းအသစ်' offered".
// Code comment (pos_screen.dart _addScannedSerial): "Already in the cart → a message, nothing added."
// HID spec (dba0348): "only while POS is on top".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
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

const _warnTitle = 'ဒီ Barcode ရှိပြီးသားပါ';
const _pickerTitle = 'ဘယ်ပစ္စည်းလဲ?';

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  Future<(ProviderContainer, _QaScanner)> boot(WidgetTester tester, {String template = 'grocery'}) async {
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
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  List<CartLine> cart(ProviderContainer c) => c.read(cartProvider).lines;

  Product product(ProviderContainer c, String name, {String? barcode, int price = 700}) => Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 500, price: price, category: 'QA', barcode: barcode,
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0,
      );
  StockMovement into(Product p, int units) =>
      restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), note: 'initial');

  Future<Product> plain(ProviderContainer c, String name, String? barcode, {int price = 700}) async {
    final p = product(c, name, barcode: barcode, price: price);
    await c.read(productServiceProvider).create(p, initialStock: [into(p, 10)]);
    return p;
  }

  void deleteInFake(ProviderContainer c, Product p) {
    final i = db(c).products.indexWhere((x) => x.id == p.id);
    db(c).products[i] = p.copyWith(deletedAt: () => DateTime.utc(2026, 11, 1));
    db(c).touch({FakeTable.products});
  }

  ProductSerial serial(Product p, String imei, {SerialStatus status = SerialStatus.inStock}) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: status, createdAt: t0, updatedAt: t0);

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

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
  }

  // ================================================================ TC-PROD-NEW-35 duplicate-barcode warning (a)
  group('TC-PROD-NEW-35 Add/Edit Product duplicate-barcode warning edges', () {
    testWidgets('a DELETED product\'s barcode is not a duplicate; Myanmar digits are compared normalized; the dialog names '
        'every other live product; "ပြန်ပြင်မယ်" saves nothing', (tester) async {
      final (c, _) = await boot(tester);
      final gone = await plain(c, 'QA R8 gone', '8850000008001');
      deleteInFake(c, gone);
      final a = await plain(c, 'QA R8 dupA', '8850000008002');
      final b = await plain(c, 'QA R8 dupB', '8850000008002');

      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R8 reuse deleted');
      await tester.enterText(field('price'), '900');
      await tester.enterText(field('barcode'), '8850000008001');
      await tapSave(tester);
      expect(find.text(_warnTitle), findsNothing, reason: '(a) "already on another LIVE product" — the other one is deleted');
      expect(db(c).products.where((p) => p.name == 'QA R8 reuse deleted' && p.barcode == '8850000008001'), hasLength(1));

      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R8 mm digits');
      await tester.enterText(field('price'), '900');
      await tester.enterText(field('barcode'), ' ၈၈၅၀၀၀၀၀၀၈၀၀၂ ');
      await tapSave(tester);
      expect(find.text(_warnTitle), findsOneWidget, reason: 'Myanmar digits = the same barcode (normalized like the server)');
      expect(find.textContaining('“${a.name}”'), findsOneWidget);
      expect(find.textContaining('“${b.name}”'), findsOneWidget, reason: 'both other products are named');
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeCancel')));
      await tester.pumpAndSettle();
      expect(db(c).products.where((p) => p.name == 'QA R8 mm digits'), isEmpty, reason: 'cancel = nothing saved');
      expect(field('productName'), findsOneWidget, reason: 'still on the form');
    });

    testWidgets('edit: changing the barcode to a duplicate warns (cancel keeps the old one, save stores it); editing the price '
        'of a product that already has a duplicate barcode does not warn again; clearing the barcode does not warn',
        (tester) async {
      final (c, _) = await boot(tester);
      await plain(c, 'QA R8 owner of X', '8850000008100');
      final b = await plain(c, 'QA R8 edit me', '8850000008199');
      Product row() => db(c).products.singleWhere((p) => p.id == b.id);

      c.read(appRouterProvider).go(Routes.editProduct(b.id));
      await tester.pumpAndSettle();
      await tester.enterText(field('barcode'), '8850000008100');
      await tapSave(tester);
      expect(find.text(_warnTitle), findsOneWidget, reason: '(a) a CHANGED barcode already on another live product');
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeCancel')));
      await tester.pumpAndSettle();
      expect(row().barcode, '8850000008199', reason: 'cancel: nothing written');
      await tapSave(tester);
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeSave')));
      await tester.pumpAndSettle();
      expect(row().barcode, '8850000008100', reason: 'warn, not block');

      c.read(appRouterProvider).go(Routes.editProduct(b.id));
      await tester.pumpAndSettle();
      await tester.enterText(field('price'), '1234');
      await tapSave(tester);
      expect(find.text(_warnTitle), findsNothing, reason: 'barcode not changed');
      expect(row().price, 1234);

      c.read(appRouterProvider).go(Routes.editProduct(b.id));
      await tester.pumpAndSettle();
      await tester.enterText(field('barcode'), '');
      await tapSave(tester);
      expect(find.text(_warnTitle), findsNothing);
      expect(row().barcode, anyOf(isNull, isEmpty));
    });
  });

  // ================================================================ TC-POS-NEW-12 duplicate-barcode picker (b)
  group('TC-POS-NEW-12 POS picker for a duplicate barcode', () {
    testWidgets('picker lists both with prices; HID bursts while it is open are ignored; dismissing adds nothing; camera scan '
        'opens it too; picking a product without a price asks the price first', (tester) async {
      final (c, scanner) = await boot(tester);
      final a = await plain(c, 'QA R8 pick A', '8850000008200', price: 700);
      final b = await plain(c, 'QA R8 pick B', '8850000008200', price: 0);
      final other = await plain(c, 'QA R8 other', '8850000008299');
      await openPos(tester, c);

      await burst(tester, '8850000008200');
      expect(find.text(_pickerTitle), findsOneWidget);
      expect(find.byKey(ValueKey('barcodeMatch-${a.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('barcodeMatch-${b.id}')), findsOneWidget);
      expect(inSheet(find.text('QA R8 pick A')), findsOneWidget);
      expect(cart(c), isEmpty);

      await burst(tester, '8850000008200');
      await burst(tester, '8850000008299');
      expect(find.text(_pickerTitle), findsOneWidget, reason: 'HID scans only while POS is on top: no 2nd picker');
      expect(cart(c), isEmpty, reason: 'a burst under the picker adds nothing (not even the other product)');

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text(_pickerTitle), findsNothing);
      expect(cart(c), isEmpty, reason: 'dismissed = nothing');

      scanner.next = '8850000008200';
      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      expect(find.text(_pickerTitle), findsOneWidget, reason: 'camera scan: same picker');
      await tester.tap(find.byKey(ValueKey('barcodeMatch-${b.id}')));
      await tester.pumpAndSettle();
      expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsOneWidget, reason: 'picked product has no price: same as a tap');
      for (final k in ['8', '0', '0']) {
        await tester.tap(inSheet(find.text(k)).first);
        await tester.pump();
      }
      await tester.tap(find.text('သိမ်းပြီး ခြင်းထဲထည့်မယ်'));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => (l.productId, l.price)), [(b.id, 800)]);

      await burst(tester, '8850000008299');
      expect(cart(c).map((l) => l.productId), [b.id, other.id], reason: 'HID works again once the picker is closed');
    });

    testWidgets('a duplicate whose other product is DELETED → no picker, the live one is added directly', (tester) async {
      final (c, _) = await boot(tester);
      final live = await plain(c, 'QA R8 live', '8850000008300');
      final gone = await plain(c, 'QA R8 gone dup', '8850000008300');
      deleteInFake(c, gone);
      await openPos(tester, c);
      await burst(tester, '8850000008300');
      expect(find.text(_pickerTitle), findsNothing);
      expect(cart(c).single.productId, live.id);
    });

    testWidgets('phone shop: a duplicate barcode shared by a phone and an accessory → pick the phone → the IMEI question '
        'follows; the picked IMEI is on the line', (tester) async {
      final (c, _) = await boot(tester, template: 'phone');
      final ph = product(c, 'QA R8 dup phone', barcode: '6901443008400', price: 450000);
      final s1 = serial(ph, '359800000000401'), s2 = serial(ph, '359800000000402');
      await c.read(productServiceProvider).create(ph, serials: [s1, s2], initialStock: [into(ph, 2)]);
      await plain(c, 'QA R8 dup case', '6901443008400', price: 5000);
      await openPos(tester, c);
      await burst(tester, '6901443008400');
      await tester.tap(find.byKey(ValueKey('barcodeMatch-${ph.id}')));
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
      await tester.tap(inSheet(find.text('359800000000402')));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => (l.productId, l.serialId)), [(ph.id, s2.id)]);
    });
  });

  // ================================================================ TC-POS-NEW-13 IMEI scan at POS (c), fake repos
  group('TC-POS-NEW-13 IMEI scanned at POS', () {
    testWidgets('IMEI already in the cart (picked by tapping the product) → message, no 2nd line', (tester) async {
      final (c, _) = await boot(tester, template: 'phone');
      final ph = product(c, 'QA R8 tap phone', barcode: '6901443008500', price: 450000);
      final s1 = serial(ph, '359800000000501');
      await c.read(productServiceProvider).create(ph, serials: [s1, serial(ph, '359800000000502')], initialStock: [into(ph, 2)]);
      await openPos(tester, c);
      await burst(tester, '6901443008500');
      await tester.tap(inSheet(find.text('359800000000501')));
      await tester.pumpAndSettle();
      expect(cart(c).single.serialId, s1.id);
      await burst(tester, '359800000000501');
      expect(cart(c), hasLength(1));
      expect(find.text('ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ'), findsOneWidget);
    });

    testWidgets('phone without a price: the IMEI scan asks the price, then adds that IMEI', (tester) async {
      final (c, _) = await boot(tester, template: 'phone');
      final ph = product(c, 'QA R8 noprice phone', price: 0);
      final s1 = serial(ph, '359800000000601');
      await c.read(productServiceProvider).create(ph, serials: [s1], initialStock: [into(ph, 1)]);
      await openPos(tester, c);
      await burst(tester, '359800000000601');
      expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsOneWidget);
      for (final k in ['9', '0', '0']) {
        await tester.tap(inSheet(find.text(k)).first);
        await tester.pump();
      }
      await tester.tap(find.text('သိမ်းပြီး ခြင်းထဲထည့်မယ်'));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => (l.productId, l.serialId, l.price)), [(ph.id, s1.id, 900)]);
    });

    testWidgets('the same IMEI in stock on TWO products (duplicateSerial, BUG-18 state): scanning the one box twice adds ONE '
        'phone; the 2nd scan gives the "already in the cart" message', (tester) async {
      final (c, _) = await boot(tester, template: 'phone');
      const imei = '359800000000701';
      final p1 = product(c, 'QA R8 twin 1', price: 450000), p2 = product(c, 'QA R8 twin 2', price: 450000);
      await c.read(productServiceProvider).create(p1, serials: [serial(p1, imei)], initialStock: [into(p1, 1)]);
      await c.read(productServiceProvider).create(p2, serials: [serial(p2, imei)], initialStock: [into(p2, 1)]);
      await openPos(tester, c);
      await burst(tester, imei);
      await burst(tester, imei);
      expect(cart(c), hasLength(1),
          reason: 'one box = one phone; code comment: "Already in the cart → a message, nothing added" '
              '(cart: ${cart(c).map((l) => '${l.name} ${l.serialId}').toList()})');
      expect(find.text('ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ'), findsOneWidget);
    });
  });
}
