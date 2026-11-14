import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/qty_sheet.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// BUG-3: with decimalQty on, the cashier can type 2.5 at checkout and the
/// owner can receive 2.5 into stock; without it, whole units only.
void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, {String? template}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    if (template != null) c.read(shopTemplateProvider.notifier).select(template);
    return c;
  }

  Future<void> keys(WidgetTester tester, List<String> ks) async {
    final sheet = find.byType(QtySheet);
    for (final k in ks) {
      await tester.tap(find.descendant(of: sheet, matching: find.text(k)).first);
      await tester.pump();
    }
  }

  testWidgets('hardware: tap the line quantity → keypad with "." → 2.5 → line total 2.5 × price', (tester) async {
    final c = await boot(tester, template: 'hardware');
    expect(c.read(tenantFeaturesProvider).decimalQty, isTrue);
    final water = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.id == SeedIds.water);
    c.read(cartProvider.notifier).addProduct(water);
    c.read(appRouterProvider).go(Routes.checkout);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('qty-${water.id}')));
    await tester.pumpAndSettle();
    expect(find.text('.'), findsOneWidget);
    await keys(tester, ['2', '.', '5']);
    expect(find.text('2.5 ခု'), findsOneWidget);
    await tester.tap(find.text('ပြောင်းမယ်'));
    await tester.pumpAndSettle();

    final line = c.read(cartProvider).lines.single;
    expect((line.qtyMilli, line.total), (2500, (water.price * 5 + 1) ~/ 2));
    expect(find.text('2.5'), findsOneWidget);

    // − from 2.5 → 1.5 → 0.5, and 0.5 stays (never jumps back up to 1).
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.bySemanticsLabel('လျှော့ရန်'));
      await tester.pumpAndSettle();
    }
    expect(c.read(cartProvider).lines.single.qtyMilli, 500);
  });

  testWidgets('grocery (decimalQty off): the keypad has no "." and the typed quantity is whole', (tester) async {
    final c = await boot(tester);
    expect(c.read(tenantFeaturesProvider).decimalQty, isFalse);
    final water = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.id == SeedIds.water);
    c.read(cartProvider.notifier).addProduct(water);
    c.read(appRouterProvider).go(Routes.checkout);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('qty-${water.id}')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(QtySheet), matching: find.text('.')), findsNothing);
    await keys(tester, ['2', '4']);
    await tester.tap(find.text('ပြောင်းမယ်'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines.single.qtyMilli, 24000);
  });

  testWidgets('hardware: "Stock ဖြည့်မယ်" accepts 0.75', (tester) async {
    final c = await boot(tester, template: 'hardware');
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    final db = c.read(fakeDatabaseProvider);
    final water = db.products.firstWhere((p) => p.id == SeedIds.water);
    await tester.tap(find.byKey(ValueKey('restock-${water.id}')));
    await tester.pumpAndSettle();
    await keys(tester, ['0', '.', '7', '5']);
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    final m = db.stock.last;
    expect((m.productId, m.type, m.qtyMilli), (water.id, StockMovementType.restock, 750));
  });

  test('setQty keeps any positive quantity; zero or less becomes one unit', () {
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    final cart = c.read(cartProvider.notifier);
    final water = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.id == SeedIds.water);
    cart.addProduct(water);
    cart.setQty(water.id, 250);
    expect(c.read(cartProvider).qtyOf(water.id), 250);
    cart.setQty(water.id, 0);
    expect(c.read(cartProvider).qtyOf(water.id), 1000);
  });
}
