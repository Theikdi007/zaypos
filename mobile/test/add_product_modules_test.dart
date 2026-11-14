import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';
import 'qa/qa_form_helpers.dart';

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
    c.read(appRouterProvider).go('/products/new');
    await tester.pumpAndSettle();
    return c;
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
  }

  testWidgets('pharmacy: saves a batch and receives stock into it', (tester) async {
    final c = await openAddProduct(tester, 'pharmacy');
    await tester.enterText(field('productName'), 'Paracetamol 500mg');
    // Expiry tracking is opt-in; tracked opening stock needs batch no. + expiry.
    await pickExpiryWarn(tester, warn30Label);
    await tester.enterText(field('batchNo'), 'B2406A');
    await pickAddProductExpiry(tester, 28);
    await tester.scrollUntilVisible(field('stockQty'), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(field('stockQty'), '40');
    await tester.pumpAndSettle();
    await save(tester);

    final db = c.read(fakeDatabaseProvider);
    final p = db.products.firstWhere((p) => p.name == 'Paracetamol 500mg');
    expect(p.expiryAlertDays, 30);
    final batches = db.batches.where((b) => b.productId == p.id).toList();
    expect(batches.single.batchNo, 'B2406A');
    expect(batches.single.qtyMilli, Qty.units(40));
    final moves = db.stock.where((m) => m.productId == p.id).toList();
    expect(moves.single.batchId, batches.single.id);
    expect(c.read(productsProvider).requireValue.firstWhere((v) => v.id == p.id).stockMilli, Qty.units(40));
  });

  testWidgets('phone: saves IMEI serials (inStock), warranty, and stock = IMEI count', (tester) async {
    final c = await openAddProduct(tester, 'phone');
    await tester.enterText(field('productName'), 'Galaxy A15');
    for (final imei in ['356984102231457', '356984102231465']) {
      await tester.scrollUntilVisible(field('imei'), 200, scrollable: find.byType(Scrollable).first);
      await tester.enterText(field('imei'), imei);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    await save(tester);

    final db = c.read(fakeDatabaseProvider);
    final p = db.products.firstWhere((p) => p.name == 'Galaxy A15');
    expect(p.warrantyMonths, 6); // design default "၆ လ"
    final serials = db.serials.where((s) => s.productId == p.id).toList();
    expect(serials.map((s) => s.serial), ['356984102231457', '356984102231465']);
    expect(serials.every((s) => s.status == SerialStatus.inStock && s.saleLineId == null), isTrue);
    expect(c.read(productsProvider).requireValue.firstWhere((v) => v.id == p.id).stockMilli, Qty.units(2));
  });
}
