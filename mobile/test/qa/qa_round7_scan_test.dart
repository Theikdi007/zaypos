// QA round 7 — barcode scanning (beta-polish dba0348). Widget tests on the real app screens with the fake repositories;
// the camera is replaced through `barcodeScannerProvider`, HID scanners are simulated with fast key events.
//
// Spec lines used (dba0348 commit / hand-over):
// - "HidScannerListener: HID (keyboard-mode) Bluetooth/USB scanners on POS — keys ≤ 60 ms apart, ≥ 4 chars, ending in
//   Enter = one scan; slower typing ignored; keys not swallowed; a scan typed into the focused search box is cleared;
//   only while POS is on top."
// - "POS: known barcode → same as tapping the product (price question / IMEI–size–batch picker); unknown → sheet
//   'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ' + 'ပစ္စည်းအသစ် ထည့်မယ်' → Add Product with the barcode filled (/products/new?barcode=)."
// - TC-PROD-04 / limits.json products.barcode: Myanmar digits → 0-9, trimmed ("normalized like the server").
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import 'package:zaypos_app/core/sync/sync_limits.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;

/// Camera stand-in: returns [next] (null = closed).
class _QaScanner implements BarcodeScanner {
  String? next;
  final titles = <String>[];

  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async {
    titles.add(title);
    return next;
  }
}

const _unknownTitle = 'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ';
const _addNew = 'ပစ္စည်းအသစ် ထည့်မယ်';

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
      // main.dart binds the bundled / cached server rules (loadLimits); without them normalize() is only trim().
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

  Product product(ProviderContainer c, String name, {String? barcode, int price = 700, int? expiryAlertDays}) => Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 500, price: price, category: 'QA', barcode: barcode,
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0, expiryAlertDays: expiryAlertDays,
      );
  StockMovement into(Product p, int units, {String? batchId, String? variantId}) => restockMovement(
      tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: batchId, variantId: variantId, note: 'initial');

  Future<Product> plain(ProviderContainer c, String name, String barcode, {int price = 700}) async {
    final p = product(c, name, barcode: barcode, price: price);
    await c.read(productServiceProvider).create(p, initialStock: [into(p, 10)]);
    return p;
  }

  Future<void> openPos(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
  }

  /// A HID scanner: every key right after the other, then Enter.
  Future<void> burst(WidgetTester tester, String s, {bool settle = true}) async {
    for (final ch in s.split('')) {
      // The listener reads only `character`; the test simulator knows key codes only for digits / a-z.
      final key = RegExp('[0-9a-z]').hasMatch(ch) ? LogicalKeyboardKey(ch.codeUnitAt(0)) : LogicalKeyboardKey.keyA;
      await tester.sendKeyEvent(key, character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    if (settle) await tester.pumpAndSettle();
  }

  /// A person: 120 ms between keys.
  Future<void> slow(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  // ================================================================ TC-POS-NEW-6 HID scanner
  group('TC-POS-NEW-6 HID (keyboard-mode) scanner on POS', () {
    testWidgets('burst twice → qty 2; slow typing, a 3-key burst and a burst without Enter are not scans; slow keys then a '
        'burst → only the burst counts', (tester) async {
      final (c, _) = await boot(tester);
      final p = await plain(c, 'QA R7 cola', '8850999000017');
      await openPos(tester, c);

      await burst(tester, '8850999000017');
      await burst(tester, '8850999000017');
      expect(cart(c).map((l) => (l.productId, l.qtyMilli)), [(p.id, 2000)], reason: 'two scans = qty 2 on one line');

      c.read(cartProvider.notifier).clear();
      await tester.pumpAndSettle();
      await slow(tester, '8850999000017');
      expect(cart(c), isEmpty, reason: 'a person typing is not a scan');
      expect(find.text(_unknownTitle), findsNothing, reason: 'a person typing is not a scan');

      await burst(tester, '885');
      expect(find.text(_unknownTitle), findsNothing, reason: '3 keys + Enter is not a scan (≥ 4 chars)');

      for (final ch in '8850999000017'.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
      }
      await tester.pumpAndSettle();
      expect(cart(c), isEmpty, reason: 'no Enter = no scan');
      expect(find.text(_unknownTitle), findsNothing, reason: 'no Enter = no scan');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));

      // A person types "12" slowly, then the scanner fires: the slow keys are not glued to the code.
      for (final ch in '12'.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      }
      await burst(tester, '8850999000017');
      expect(cart(c).map((l) => (l.productId, l.qtyMilli)), [(p.id, 1000)], reason: 'slow "12" not glued to the scan');
    });

    testWidgets('the scanner also typed the code into the search box → box cleared and the grid shows every product again; '
        'unrelated search text is kept', (tester) async {
      final (c, _) = await boot(tester);
      final p = await plain(c, 'QA R7 soap', '4801234567890');
      await openPos(tester, c);
      final search = find.byType(EditableText).first;
      await tester.tap(search);
      await tester.enterText(search, '4801234567890'); // what the scanner's keys put into the focused box
      await tester.pumpAndSettle();
      expect(find.text('QA R7 soap'), findsNothing, reason: 'name search "4801…" hides the product');
      await burst(tester, '4801234567890');
      expect(tester.widget<EditableText>(search).controller.text, '');
      expect(find.text('QA R7 soap'), findsOneWidget, reason: 'query reset: the grid is unfiltered again');
      expect(cart(c).single.productId, p.id);

      await tester.enterText(search, 'QA R7');
      await tester.pumpAndSettle();
      await burst(tester, '4801234567890');
      expect(tester.widget<EditableText>(search).controller.text, 'QA R7', reason: 'text that is not the scan stays');
      expect(cart(c).single.qtyMilli, 2000);
    });

    testWidgets('only while POS is on top: under Checkout, under an open sheet, under Add Product pushed from POS and on '
        'another tab a burst does nothing; back on POS it works', (tester) async {
      final (c, _) = await boot(tester);
      final p = await plain(c, 'QA R7 tea', '8851111111110');
      await openPos(tester, c);
      await burst(tester, '8851111111110');
      expect(cart(c).single.qtyMilli, 1000);

      // Checkout on top
      c.read(appRouterProvider).push(Routes.checkout);
      await tester.pumpAndSettle();
      await burst(tester, '8851111111110');
      await burst(tester, '7770000000001'); // unknown
      expect((cart(c).single.qtyMilli, find.text(_unknownTitle).evaluate().length), (1000, 0), reason: 'under Checkout');
      c.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      await burst(tester, '8851111111110');
      expect(cart(c).single.qtyMilli, 2000, reason: 'back on POS');

      // An open sheet (the unknown-barcode sheet itself)
      await burst(tester, '7770000000001');
      expect(find.text(_unknownTitle), findsOneWidget);
      await burst(tester, '8851111111110');
      await burst(tester, '7770000000002');
      expect((cart(c).single.qtyMilli, find.text(_unknownTitle).evaluate().length), (2000, 1),
          reason: 'sheet open: no add, no second sheet');

      // Add Product pushed from that sheet: a scan into ITS barcode field must not reach POS
      await tester.tap(find.text(_addNew));
      await tester.pumpAndSettle();
      expect(find.text('ပစ္စည်းအသစ်'), findsOneWidget);
      await burst(tester, '8851111111110');
      expect((cart(c).single.qtyMilli, find.text(_unknownTitle).evaluate().length), (2000, 0),
          reason: 'Add Product on top of POS');

      // Another tab: POS is gone
      c.read(appRouterProvider).go(Routes.products);
      await tester.pumpAndSettle();
      await burst(tester, '8851111111110');
      expect(cart(c).single.qtyMilli, 2000, reason: 'Products tab');
      expect(cart(c).single.productId, p.id);
    });
  });

  // ================================================================ TC-POS-NEW-7 module / no-price products scanned
  group('TC-POS-NEW-7 scanning = tapping the product', () {
    testWidgets('phone: IMEI picker (in-stock only) → picked IMEI on the line; a 2nd scan does not offer it again',
        (tester) async {
      final (c, scanner) = await boot(tester, template: 'phone');
      final p = product(c, 'QA R7 phone', barcode: '6901443000011');
      ProductSerial s(String imei, SerialStatus st) => ProductSerial(
          id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: st, createdAt: t0, updatedAt: t0);
      final a = s('359000000000011', SerialStatus.inStock);
      await c.read(productServiceProvider).create(p,
          serials: [a, s('359000000000012', SerialStatus.inStock), s('359000000000013', SerialStatus.sold)],
          initialStock: [into(p, 2)]);
      await openPos(tester, c);
      scanner.next = '6901443000011';
      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
      expect(inSheet(find.text('359000000000013')), findsNothing, reason: 'sold IMEI not offered');
      await tester.tap(inSheet(find.text('359000000000011')));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => (l.productId, l.serialId)), [(p.id, a.id)]);

      await burst(tester, '6901443000011');
      expect(inSheet(find.text('359000000000011')), findsNothing, reason: 'IMEI already in the cart');
      expect(inSheet(find.text('359000000000012')), findsOneWidget);
    });

    testWidgets('fashion: size/colour sheet → picked variant on the line', (tester) async {
      final (c, _) = await boot(tester, template: 'fashion');
      final p = product(c, 'QA R7 shirt', barcode: '8850000000303');
      ProductVariant v(String size) =>
          ProductVariant(id: newId(), tenantId: p.tenantId, productId: p.id, size: size, color: 'အပြာ', createdAt: t0, updatedAt: t0);
      final m = v('M'), xl = v('XL');
      await c.read(productServiceProvider).create(p, variants: [m, xl],
          initialStock: [into(p, 3, variantId: m.id), into(p, 2, variantId: xl.id)]);
      await openPos(tester, c);
      await burst(tester, '8850000000303');
      expect(inSheet(find.text(xl.label)), findsOneWidget);
      await tester.tap(inSheet(find.text(xl.label)));
      await tester.pumpAndSettle();
      expect(cart(c).map((l) => (l.productId, l.variantId)), [(p.id, xl.id)]);
    });

    testWidgets('pharmacy: two batches → batch sheet (earliest first); one batch → auto-picked', (tester) async {
      final (c, _) = await boot(tester, template: 'pharmacy');
      final p = product(c, 'QA R7 med', barcode: '8850000000501', expiryAlertDays: 30);
      ProductBatch b(String no, DateTime exp) =>
          ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: no, qtyMilli: 0, expiryDate: exp, createdAt: t0, updatedAt: t0);
      final late = b('LATE', DateTime.utc(2029, 6, 1)), early = b('EARLY', DateTime.utc(2028, 6, 1));
      await c.read(productServiceProvider).create(p, batches: [late, early],
          initialStock: [into(p, 2, batchId: late.id), into(p, 2, batchId: early.id)]);
      final q = product(c, 'QA R7 med one', barcode: '8850000000502', expiryAlertDays: 30);
      final only = ProductBatch(id: newId(), tenantId: q.tenantId, productId: q.id, batchNo: 'ONE', qtyMilli: 0,
          expiryDate: DateTime.utc(2029, 1, 1), createdAt: t0, updatedAt: t0);
      await c.read(productServiceProvider).create(q, batches: [only], initialStock: [into(q, 3, batchId: only.id)]);
      await openPos(tester, c);

      await burst(tester, '8850000000501');
      expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget);
      final titles = tester.widgetList<Text>(inSheet(find.byType(Text))).map((t) => t.data ?? '').toList();
      expect(titles.indexWhere((s) => s.startsWith('EARLY')), lessThan(titles.indexWhere((s) => s.startsWith('LATE'))));
      await tester.tap(inSheet(find.textContaining('EARLY')));
      await tester.pumpAndSettle();
      await burst(tester, '8850000000502');
      expect(cart(c).map((l) => (l.productId, l.batchId)), [(p.id, early.id), (q.id, only.id)]);
    });

    testWidgets('no price yet: the price question comes first; dismissing it adds nothing; a deleted product\'s barcode '
        'is unknown', (tester) async {
      final (c, _) = await boot(tester);
      final p = await plain(c, 'QA R7 noprice', '8850000000709', price: 0);
      final gone = await plain(c, 'QA R7 gone', '8850000000808');
      final i = db(c).products.indexWhere((x) => x.id == gone.id);
      db(c).products[i] = gone.copyWith(deletedAt: () => DateTime.utc(2026, 11, 1));
      db(c).touch({FakeTable.products});
      await openPos(tester, c);
      await burst(tester, '8850000000709');
      expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsOneWidget, reason: 'same as tapping a product without a price');
      await tester.tapAt(const Offset(195, 40)); // outside the sheet
      await tester.pumpAndSettle();
      expect(cart(c), isEmpty);
      expect(c.read(catalogProvider).value!.firstWhere((x) => x.id == p.id).price, 0);

      await burst(tester, '8850000000808');
      expect(find.text(_unknownTitle), findsOneWidget, reason: 'deleted product is not found by its barcode');
    });
  });

  // ================================================================ TC-POS-NEW-11 risky inputs (no spec line beyond README §3.4)
  group('TC-POS-NEW-11 duplicate barcode on one phone; IMEI scanned at POS', () {
    // Updated to the owner decisions of 2026-11-14 (developer, with the change; QA round 8 re-checks):
    // duplicate barcode → warn on save (not blocked) and a picker at POS; an in-stock IMEI scanned at POS → that phone.
    testWidgets('two products with one barcode: Add Product warns but saves the 2nd; a scan opens a picker with both '
        '(nothing auto-picked)', (tester) async {
      final (c, _) = await boot(tester);
      final first = await plain(c, 'QA R7 dup first', '8850000001111');
      await openPos(tester, c);
      c.read(appRouterProvider).push(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R7 dup second');
      await tester.enterText(field('price'), '900');
      await tester.enterText(field('barcode'), '8850000001111');
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(find.text('ဒီ Barcode ရှိပြီးသားပါ'), findsOneWidget, reason: 'owner: warn');
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeSave')));
      await tester.pumpAndSettle();
      final both = db(c).products.where((p) => p.barcode == '8850000001111').toList();
      expect(both, hasLength(2), reason: 'owner: warn, do not block');
      await burst(tester, '8850000001111');
      expect(cart(c), isEmpty, reason: 'owner: a picker instead of auto-picking');
      expect(find.byKey(ValueKey('barcodeMatch-${first.id}')), findsOneWidget);
      // QA round 8: the title says "a picker with both" — check the second one is listed too.
      final second = both.singleWhere((p) => p.id != first.id);
      expect(find.byKey(ValueKey('barcodeMatch-${second.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('barcodeMatch-${first.id}')));
      await tester.pumpAndSettle();
      expect(cart(c).single.productId, first.id);
    });

    testWidgets('phone shop: scanning an in-stock IMEI (box sticker) at POS adds that phone with that IMEI', (tester) async {
      final (c, _) = await boot(tester, template: 'phone');
      final p = product(c, 'QA R7 phone2', barcode: '6901443000099');
      await c.read(productServiceProvider).create(p, serials: [
        ProductSerial(id: newId(), tenantId: p.tenantId, productId: p.id, serial: '359000000000099',
            status: SerialStatus.inStock, createdAt: t0, updatedAt: t0),
      ], initialStock: [into(p, 1)]);
      await openPos(tester, c);
      await burst(tester, '359000000000099');
      expect(find.text(_unknownTitle), findsNothing, reason: 'owner: look up in-stock IMEIs');
      expect(cart(c).single.productId, p.id);
      expect(cart(c).single.serialId, db(c).serials.singleWhere((s) => s.serial == '359000000000099').id);
    });
  });

  // ================================================================ TC-POS-NEW-8 normalization + unknown-barcode flow
  group('TC-POS-NEW-8 normalization and the unknown-barcode flow', () {
    testWidgets('camera code with Myanmar digits and spaces finds the product saved with 0-9', (tester) async {
      final (c, scanner) = await boot(tester);
      final p = await plain(c, 'QA R7 rice', '8850123456789');
      await openPos(tester, c);
      scanner.next = '  ၈၈၅၀၁၂၃၄၅၆၇၈၉ ';
      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      expect(cart(c).single.productId, p.id);
      expect(scanner.titles, ['Barcode ဖတ်မယ်']);
    });

    testWidgets('unknown code → sheet shows the normalized code; "မလုပ်တော့ပါ" changes nothing; "ပစ္စည်းအသစ် ထည့်မယ်" → '
        'Add Product with the code (special characters kept) → save → back on POS the same scan adds it', (tester) async {
      final (c, scanner) = await boot(tester);
      await openPos(tester, c);
      final before = db(c).products.length;
      scanner.next = ' ၄၇၁၂-A&B=1+2 ';
      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      expect(find.text(_unknownTitle), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('unknownBarcode'))).data, '4712-A&B=1+2');
      await tester.tap(find.text('မလုပ်တော့ပါ'));
      await tester.pumpAndSettle();
      expect((find.text(_unknownTitle).evaluate().length, db(c).products.length, cart(c).length), (0, before, 0));

      await tester.tap(find.byKey(const ValueKey('posScan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_addNew));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field('barcode')).controller.text, '4712-A&B=1+2',
          reason: 'query string round trip keeps & = +');
      await tester.enterText(field('productName'), 'QA R7 scanned new');
      await tester.enterText(field('price'), '900');
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      final saved = db(c).products.singleWhere((x) => x.name == 'QA R7 scanned new');
      expect(saved.barcode, '4712-A&B=1+2');
      expect(find.byKey(const ValueKey('posScan')), findsOneWidget, reason: 'back on POS');
      expect(cart(c), isEmpty, reason: 'creating it does not sell it');

      await burst(tester, '4712-A&B=1+2');
      expect(cart(c).single.productId, saved.id, reason: 'the new product is found by the same code');
    });

    testWidgets('Add Product scan: Myanmar digits stored as 0-9; IMEI scan adds once (a 2nd scan of the same IMEI is refused); '
        'closing the camera changes nothing', (tester) async {
      final (c, scanner) = await boot(tester, template: 'phone');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('barcode'), '111');
      scanner.next = null;
      await tester.tap(find.byKey(const ValueKey('barcodeScan')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field('barcode')).controller.text, '111', reason: 'camera closed');
      scanner.next = '၈၈၅၀၀၀၀၀၀၀၀၁၇';
      await tester.tap(find.byKey(const ValueKey('barcodeScan')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field('barcode')).controller.text, '8850000000017');

      scanner.next = '356984102231458';
      await tester.scrollUntilVisible(find.byKey(const ValueKey('imeiScan')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('imeiScan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('imeiScan')));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is Text && w.data == '356984102231458'), findsOneWidget,
          reason: 'listed once (the field may still hold the refused duplicate)');
      expect(find.text('ဒီ IMEI ထည့်ပြီးသားပါ။'), findsOneWidget, reason: 'same message as typing a duplicate');
      expect(scanner.titles, ['Barcode ဖတ်မယ်', 'Barcode ဖတ်မယ်', 'IMEI ဖတ်မယ်', 'IMEI ဖတ်မယ်']);
    });
  });
}
