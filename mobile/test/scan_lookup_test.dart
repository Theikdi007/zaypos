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
import 'package:zaypos_app/main.dart';

import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// Owner decisions 2026-11-14:
/// - duplicate barcode: Add/Edit Product warns (does not block); a POS scan
///   matching several products opens a picker instead of choosing one.
/// - phone shops: a scanned in-stock IMEI adds that phone with that IMEI; only
///   when neither a barcode nor an in-stock IMEI matches is "ပစ္စည်းအသစ်" offered.
void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);
  const unknownTitle = 'ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ';

  Future<ProviderContainer> boot(WidgetTester tester, {String template = 'grocery'}) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  List<CartLine> cart(ProviderContainer c) => c.read(cartProvider).lines;

  Future<Product> create(ProviderContainer c, String name, {String? barcode, int price = 700, List<String> imeis = const []}) async {
    final p = Product(
      id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 500, price: price, category: 'QA',
      barcode: barcode, tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0,
    );
    await c.read(productServiceProvider).create(
      p,
      serials: [
        for (final i in imeis)
          ProductSerial(id: newId(), tenantId: p.tenantId, productId: p.id, serial: i, status: SerialStatus.inStock,
              createdAt: t0, updatedAt: t0),
      ],
      initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(imeis.isEmpty ? 10 : imeis.length), note: 'initial'),
      ],
    );
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

  Future<void> burst(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSave(WidgetTester tester, String name, String barcode) async {
    await tester.enterText(field('productName'), name);
    await tester.enterText(field('price'), '900');
    await tester.enterText(field('barcode'), barcode);
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
  }

  group('duplicate barcode', () {
    testWidgets('Add Product warns with the other product; "ပြန်ပြင်မယ်" keeps the form, "ဒီအတိုင်း သိမ်းမယ်" saves',
        (tester) async {
      final c = await boot(tester);
      await create(c, 'Dup first', barcode: '8850000001111');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();

      await fillAndSave(tester, 'Dup second', '8850000001111');
      expect(find.text('ဒီ Barcode ရှိပြီးသားပါ'), findsOneWidget);
      expect(find.textContaining('“Dup first”'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeCancel')));
      await tester.pumpAndSettle();
      expect(db(c).products.where((p) => p.name == 'Dup second'), isEmpty);
      expect(field('productName'), findsOneWidget, reason: 'still on the form');

      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duplicateBarcodeSave')));
      await tester.pumpAndSettle();
      expect(db(c).products.where((p) => p.barcode == '8850000001111'), hasLength(2));
    });

    testWidgets('a unique barcode, or editing a product without changing its barcode, saves without the warning',
        (tester) async {
      final c = await boot(tester);
      await create(c, 'Dup first', barcode: '8850000001111');
      final second = await create(c, 'Dup second', barcode: '8850000001111');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await fillAndSave(tester, 'Unique one', '8850000002222');
      expect(find.text('ဒီ Barcode ရှိပြီးသားပါ'), findsNothing);
      expect(db(c).products.where((p) => p.name == 'Unique one'), hasLength(1));

      c.read(appRouterProvider).go(Routes.editProduct(second.id));
      await tester.pumpAndSettle();
      await tester.enterText(field('price'), '950');
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(find.text('ဒီ Barcode ရှိပြီးသားပါ'), findsNothing);
      expect(db(c).products.singleWhere((p) => p.id == second.id).price, 950);
    });

    testWidgets('POS: a scan matching two products opens a picker; the picked one is added; dismissing adds nothing',
        (tester) async {
      final c = await boot(tester);
      final a = await create(c, 'Dup A', barcode: '8850000001111', price: 700);
      final b = await create(c, 'Dup B', barcode: '8850000001111', price: 900);
      await openPos(tester, c);

      await burst(tester, '8850000001111');
      expect(find.text('ဘယ်ပစ္စည်းလဲ?'), findsOneWidget);
      expect(find.byKey(ValueKey('barcodeMatch-${a.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('barcodeMatch-${b.id}')), findsOneWidget);
      expect(cart(c), isEmpty, reason: 'nothing auto-picked');
      await tester.tap(find.byKey(ValueKey('barcodeMatch-${b.id}')));
      await tester.pumpAndSettle();
      expect(cart(c).single.productId, b.id);

      await burst(tester, '8850000001111');
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();
      expect(cart(c).single.qtyMilli, Qty.units(1), reason: 'dismissed: nothing added');
    });

    testWidgets('POS: a barcode on one product only is still added directly', (tester) async {
      final c = await boot(tester);
      final a = await create(c, 'Only one', barcode: '8850000003333');
      await openPos(tester, c);
      await burst(tester, '8850000003333');
      expect(find.text('ဘယ်ပစ္စည်းလဲ?'), findsNothing);
      expect(cart(c).single.productId, a.id);
    });
  });

  group('IMEI scan at POS (phone shop)', () {
    testWidgets('an in-stock IMEI adds that phone with that IMEI; the same IMEI again → message, no 2nd line', (tester) async {
      final c = await boot(tester, template: 'phone');
      final p = await create(c, 'Phone X', barcode: '6901443000099', imeis: ['359000000000011', '359000000000022']);
      await openPos(tester, c);

      await burst(tester, '359000000000022');
      expect(find.text('ဘယ် IMEI လဲ?'), findsNothing, reason: 'the IMEI is known: no question');
      final line = cart(c).single;
      expect(line.productId, p.id);
      final row = db(c).serials.singleWhere((s) => s.serial == '359000000000022');
      expect(line.serialId, row.id);

      await burst(tester, '359000000000022');
      expect(find.text('ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ'), findsOneWidget);
      expect(cart(c), hasLength(1));
      expect(find.text(unknownTitle), findsNothing);
    });

    testWidgets('the product barcode still asks which IMEI; a sold IMEI → "sold" message (no "ပစ္စည်းအသစ်"); '
        'an unknown IMEI → "ပစ္စည်းအသစ်" sheet', (tester) async {
      final c = await boot(tester, template: 'phone');
      await create(c, 'Phone Y', barcode: '6901443000088', imeis: ['359000000000033']);
      final sold = db(c).serials.singleWhere((s) => s.serial == '359000000000033');
      db(c).serials[db(c).serials.indexOf(sold)] = ProductSerial(
        id: sold.id, tenantId: sold.tenantId, productId: sold.productId, serial: sold.serial,
        status: SerialStatus.sold, createdAt: sold.createdAt, updatedAt: sold.updatedAt,
      );
      await openPos(tester, c);

      await burst(tester, '359000000000033');
      expect(find.text("ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ"), findsOneWidget);
      expect(find.text(unknownTitle), findsNothing, reason: 'owner: no "ပစ္စည်းအသစ်" for a sold IMEI');
      expect(cart(c), isEmpty);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await burst(tester, '359000000000099');
      expect(find.text(unknownTitle), findsOneWidget);
      await tester.tap(find.text('မလုပ်တော့ပါ'));
      await tester.pumpAndSettle();

      await burst(tester, '6901443000088');
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget, reason: 'barcode → same as a tap');
    });

    testWidgets('BUG-28: one IMEI on two products — after scanning it, tapping the twin product does not offer it again',
        (tester) async {
      final c = await boot(tester, template: 'phone');
      await create(c, 'Phone R', imeis: ['359000000000066']);
      await create(c, 'Phone S', imeis: ['359000000000066', '359000000000077']);
      await openPos(tester, c);
      await burst(tester, '359000000000066');
      expect(cart(c), hasLength(1));

      await tester.enterText(find.byType(EditableText).first, 'Phone S');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone S').last);
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
      expect(find.text('359000000000066'), findsNothing, reason: 'already in the cart (from Phone R)');
      expect(find.text('359000000000077'), findsOneWidget);
    });

    testWidgets('BUG-27: one IMEI in stock on two products (duplicateSerial) — the 2nd scan is refused by IMEI value',
        (tester) async {
      final c = await boot(tester, template: 'phone');
      await create(c, 'Phone P', imeis: ['359000000000044']);
      await create(c, 'Phone Q', imeis: ['359000000000044']);
      await openPos(tester, c);
      await burst(tester, '359000000000044');
      expect(cart(c), hasLength(1));
      await burst(tester, '359000000000044');
      expect(find.text('ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ'), findsOneWidget);
      expect(cart(c), hasLength(1), reason: 'never two phones for one IMEI');
    });

    testWidgets('a traded-in IMEI (old row sold, new row in stock) adds the new row; an IMEI picked by tapping the product '
        'is also refused when scanned', (tester) async {
      final c = await boot(tester, template: 'phone');
      final p = await create(c, 'Phone T', barcode: '6901443000077', imeis: ['359000000000055']);
      final old = db(c).serials.single;
      db(c).serials[0] = ProductSerial(id: old.id, tenantId: old.tenantId, productId: old.productId, serial: old.serial,
          status: SerialStatus.sold, createdAt: old.createdAt, updatedAt: old.updatedAt);
      final fresh = ProductSerial(id: newId(), tenantId: p.tenantId, productId: p.id, serial: old.serial,
          status: SerialStatus.inStock, createdAt: t0.add(const Duration(days: 1)), updatedAt: t0.add(const Duration(days: 1)));
      db(c).serials.add(fresh);
      await openPos(tester, c);
      await burst(tester, '359000000000055');
      expect(cart(c).single.serialId, fresh.id);
      await burst(tester, '359000000000055');
      expect(find.text('ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ'), findsOneWidget);
      expect(find.textContaining('ရောင်းပြီးသားပါ'), findsNothing);
      expect(cart(c), hasLength(1));
    });

    testWidgets('shops without IMEI tracking do not look serials up', (tester) async {
      final c = await boot(tester);
      await openPos(tester, c);
      await burst(tester, '359000000000011');
      expect(find.text(unknownTitle), findsOneWidget);
    });
  });
}
