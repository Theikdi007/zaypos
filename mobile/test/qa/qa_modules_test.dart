// QA round 1 — product modules (variants / IMEI / batch) through the real screens:
// TC-PROD-11 and TC-POS-NEW-2 (selling a module product records WHICH variant/IMEI/batch).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> openAddProduct(WidgetTester tester, String template) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    return c;
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.scrollUntilVisible(field(key), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(field(key), text);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
  }

  /// POS → products → tap [name] once → checkout (cash, exact) → confirm.
  Future<void> sellOnce(WidgetTester tester, ProviderContainer c, String name) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, name);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
    // If the app asks which IMEI / size / batch, pick the first offered option.
    final sheet = find.byType(BottomSheet);
    if (sheet.evaluate().isNotEmpty) {
      await tester.tap(find.descendant(of: sheet, matching: find.byType(InkWell)).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
  }

  // ---------------------------------------------------------------- TC-PROD-11
  testWidgets('TC-PROD-11 fashion: sizes M,L × colours black,white → 4 variants, each with its own stock', (tester) async {
    final c = await openAddProduct(tester, 'fashion');
    await tester.enterText(field('productName'), 'QA ရှပ်အင်္ကျီ');
    await tester.enterText(field('price'), '15000');
    const stock = {'M · အနက်': 3, 'M · အဖြူ': 2, 'L · အနက်': 1, 'L · အဖြူ': 4};
    for (final e in stock.entries) {
      await enter(tester, e.key, '${e.value}');
    }
    await save(tester);

    final db = c.read(fakeDatabaseProvider);
    final p = db.products.firstWhere((p) => p.name == 'QA ရှပ်အင်္ကျီ');
    final variants = db.variants.where((v) => v.productId == p.id).toList();
    expect(variants.map((v) => '${v.size} · ${v.color}').toSet(), stock.keys.toSet());
    for (final v in variants) {
      final own = db.stock.where((m) => m.variantId == v.id).fold<int>(0, (a, m) => a + m.qtyMilli);
      expect(own, Qty.units(stock['${v.size} · ${v.color}']!), reason: '${v.size} · ${v.color}');
    }
    expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).stockMilli, Qty.units(10));
  });

  // ---------------------------------------------------------------- TC-POS-NEW-2
  group('TC-POS-NEW-2 selling a module product records which IMEI / variant / batch', () {
    testWidgets('phone: selling a phone with 2 IMEIs marks one IMEI sold', (tester) async {
      final c = await openAddProduct(tester, 'phone');
      await tester.enterText(field('productName'), 'QA Galaxy A15');
      await tester.enterText(field('price'), '450000');
      for (final imei in ['356984102231457', '356984102231465']) {
        await enter(tester, 'imei', imei);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      await save(tester);
      final db = c.read(fakeDatabaseProvider);
      final p = db.products.firstWhere((p) => p.name == 'QA Galaxy A15');

      await sellOnce(tester, c, 'QA Galaxy A15');

      final line = db.sales.expand((s) => s.lines).firstWhere((l) => l.productId == p.id);
      final serials = db.serials.where((s) => s.productId == p.id).toList();
      expect(line.serialId, isNotNull, reason: 'the sale line must say which IMEI was sold');
      expect(serials.where((s) => s.status == SerialStatus.sold), hasLength(1),
          reason: 'stock is now 1, so exactly one IMEI must be sold (in-stock IMEIs must equal stock)');
    });

    testWidgets('fashion: selling a shirt records the size/colour variant', (tester) async {
      final c = await openAddProduct(tester, 'fashion');
      await tester.enterText(field('productName'), 'QA ရှပ်');
      await tester.enterText(field('price'), '15000');
      await enter(tester, 'M · အနက်', '3');
      await save(tester);
      final db = c.read(fakeDatabaseProvider);
      final p = db.products.firstWhere((p) => p.name == 'QA ရှပ်');

      await sellOnce(tester, c, 'QA ရှပ်');

      final line = db.sales.expand((s) => s.lines).firstWhere((l) => l.productId == p.id);
      expect(line.variantId, isNotNull, reason: 'variant stock can only go down if the sale names the variant');
      final saleMove = db.stock.firstWhere((m) => m.productId == p.id && m.qtyMilli < 0);
      expect(saleMove.variantId, isNotNull);
    });

    testWidgets('pharmacy: selling from a batch reduces that batch', (tester) async {
      final c = await openAddProduct(tester, 'pharmacy');
      await tester.enterText(field('productName'), 'QA Paracetamol');
      await tester.enterText(field('price'), '150');
      await enter(tester, 'batchNo', 'B1');
      await enter(tester, 'stockQty', '40');
      await save(tester);
      final db = c.read(fakeDatabaseProvider);
      final p = db.products.firstWhere((p) => p.name == 'QA Paracetamol');

      await sellOnce(tester, c, 'QA Paracetamol');

      final line = db.sales.expand((s) => s.lines).firstWhere((l) => l.productId == p.id);
      expect(line.batchId, isNotNull, reason: 'batch stock (= sum of its movements) must drop with the sale');
    });
  });
}
