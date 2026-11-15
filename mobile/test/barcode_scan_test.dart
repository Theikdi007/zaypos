import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_view.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// Camera scanner stand-in: returns [next] (null = the user closed it).
class FakeBarcodeScanner implements BarcodeScanner {
  String? next;
  int calls = 0;

  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async {
    calls++;
    return next;
  }
}

/// Barcode scanning (beta-polish item 1): camera on POS and Add/Edit Product,
/// HID (keyboard-mode) scanners on POS.
void main() {
  setUpAll(loadAppFonts);

  const code = '8850999320014';

  Future<(ProviderContainer, FakeBarcodeScanner, Product)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scanner = FakeBarcodeScanner();
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      barcodeScannerProvider.overrideWithValue(scanner),
    ]);
    addTearDown(c.dispose);
    final t = nowUtc();
    final p = Product(
      id: newId(), tenantId: c.read(tenantIdProvider), name: 'QA Coke can', cost: 500, price: 700,
      category: 'အချိုရည်', barcode: code, tint: 0, initial: 'C', createdAt: t, updatedAt: t,
    );
    await c.read(productServiceProvider).create(p);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, scanner, p);
  }

  Future<void> openPosProducts(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> typeBurst(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  test('productByBarcode normalizes like the server (spaces trimmed)', () {
    final t = nowUtc();
    final v = [
      for (final b in ['111', code])
        ProductView(Product(id: b, tenantId: 't', name: b, cost: 0, price: 1, category: 'x', barcode: b,
            tint: 0, initial: 'x', createdAt: t, updatedAt: t), 0),
    ];
    expect(productByBarcode(v, '  $code ', bundledLimits())?.product.id, code);
    expect(productByBarcode(v, '999', bundledLimits()), isNull);
    expect(productByBarcode(v, '   ', bundledLimits()), isNull);
  });

  testWidgets('POS camera scan of a known barcode adds the product to the cart', (tester) async {
    final (c, scanner, p) = await boot(tester);
    await openPosProducts(tester, c);
    scanner.next = code;
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await tester.pumpAndSettle();
    expect(scanner.calls, 1);
    expect(c.read(cartProvider).lines.single.productId, p.id);
    // Closing the scanner does nothing.
    scanner.next = null;
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines.single.qtyMilli, 1000);
  });

  testWidgets('POS: unknown barcode → "ပစ္စည်းအသစ် ထည့်မယ်" → Add Product with the barcode filled in', (tester) async {
    final (c, scanner, _) = await boot(tester);
    await openPosProducts(tester, c);
    scanner.next = '4712345678901';
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await tester.pumpAndSettle();
    expect(find.text('ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ'), findsOneWidget);
    expect(find.text('4712345678901'), findsOneWidget);
    await tester.tap(find.text('ပစ္စည်းအသစ် ထည့်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ပစ္စည်းအသစ်'), findsOneWidget, reason: 'Add Product opened');
    final field = find.descendant(of: find.byKey(const ValueKey('barcode')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(field).controller.text, '4712345678901');
    expect(c.read(cartProvider).lines, isEmpty);
  });

  testWidgets('POS: a HID scanner burst (fast keys + Enter) adds the product; the search box is cleared', (tester) async {
    final (c, _, p) = await boot(tester);
    await openPosProducts(tester, c);
    await tester.tap(find.byType(EditableText).first); // search focused: the scanner types into it too
    await tester.pump();
    await typeBurst(tester, code);
    expect(c.read(cartProvider).lines.single.productId, p.id);
    expect(tester.widget<EditableText>(find.byType(EditableText).first).controller.text, '');
  });

  testWidgets('POS: slow typing + Enter (a person) is not a scan', (tester) async {
    final (c, _, _) = await boot(tester);
    await openPosProducts(tester, c);
    for (final ch in code.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines, isEmpty);
    expect(find.text('ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ'), findsNothing);
  });

  testWidgets('Add Product: the barcode scan button fills the field; phone template: IMEI scan adds the IMEI',
      (tester) async {
    final (c, scanner, _) = await boot(tester);
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    scanner.next = ' 4800016644238 ';
    await tester.tap(find.byKey(const ValueKey('barcodeScan')));
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byKey(const ValueKey('barcode')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(field).controller.text, '4800016644238');

    c.read(shopTemplateProvider.notifier).select('phone');
    c.read(appRouterProvider).go(Routes.dashboard);
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    scanner.next = '356984102231457';
    await tester.scrollUntilVisible(find.byKey(const ValueKey('imeiScan')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('imeiScan')));
    await tester.pumpAndSettle();
    expect(find.text('356984102231457'), findsOneWidget, reason: 'added to the IMEI list');
  });

  testWidgets('Edit Product: barcode scan replaces the barcode', (tester) async {
    final (c, scanner, p) = await boot(tester);
    c.read(appRouterProvider).go(Routes.editProduct(p.id));
    await tester.pumpAndSettle();
    scanner.next = '0000000000017';
    await tester.tap(find.byKey(const ValueKey('barcodeScan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    expect(c.read(catalogProvider).value!.firstWhere((x) => x.id == p.id).barcode, '0000000000017');
  });
}
