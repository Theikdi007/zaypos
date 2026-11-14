import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/core/widgets/common.dart' show FilterChips;
import 'package:zaypos_app/core/widgets/product_tile.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_view.dart';
import 'package:zaypos_app/features/products/presentation/products_screen.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// Products never counted in (e.g. imported presets) are "Stock မမှတ်ရသေး":
/// grey, never "ကုန်", and outside every low/out count.
void main() {
  setUpAll(loadAppFonts);

  Product preset(String tenantId, String name, {int price = 1000}) {
    final t = nowUtc();
    return Product(
      id: newId(),
      tenantId: tenantId,
      name: name,
      cost: 0,
      price: price,
      category: 'စားသောက်ကုန်',
      tint: 0xFFFEF3C7,
      initial: name.characters.first,
      createdAt: t,
      updatedAt: t,
    );
  }

  /// Seed shop + [n] untracked presets (one already sold, i.e. negative ledger).
  Future<(ProviderContainer, List<Product>)> boot(WidgetTester tester, {int n = 3}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    final tenantId = c.read(tenantIdProvider);
    final presets = [for (var i = 0; i < n; i++) preset(tenantId, 'ပဲဆီ ${'ABCDEFGH'[i]}')];
    final t = nowUtc();
    c.read(fakeDatabaseProvider)
      ..products.addAll(presets)
      ..stock.add(StockMovement(
        id: newId(), tenantId: tenantId, productId: presets.first.id,
        type: StockMovementType.sale, qtyMilli: -Qty.units(1), createdAt: t, updatedAt: t,
      ))
      ..touch({FakeTable.products, FakeTable.stock});
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, presets);
  }

  Future<void> openProducts(WidgetTester tester, ProviderContainer c, {String filter = ''}) async {
    c.read(appRouterProvider).go(filter.isEmpty ? Routes.products : '${Routes.products}?filter=$filter');
    await tester.pumpAndSettle();
  }

  testWidgets('Dashboard low-stock card and Products "Stock နည်း" filter show the same number; untracked excluded',
      (tester) async {
    final (c, _) = await boot(tester);
    final views = c.read(productsProvider).requireValue;
    final expected = views.where((p) => p.needsRestock).length;
    expect(expected, greaterThan(0), reason: 'seed has low (oil, soap) and out (coffee) products');
    expect(views.where((p) => p.isUntracked).length, 3);

    expect(find.text('$expected မျိုး'), findsOneWidget);

    await openProducts(tester, c);
    expect(find.text('Stock နည်း ($expected)'), findsOneWidget);
    expect(find.text('Stock မမှတ်ရသေး (3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the Dashboard low-stock card opens Products filtered to "Stock နည်း"', (tester) async {
    final (c, presets) = await boot(tester);
    final low = c.read(productsProvider).requireValue.where((p) => p.needsRestock).toList();

    await tester.tap(find.text('Stock နည်းနေသည်'));
    await tester.pumpAndSettle();

    final screen = tester.widget<ProductsScreen>(find.byType(ProductsScreen));
    expect(screen.initialFilter, ProductFilter.low);
    final chips = tester.widget<FilterChips<ProductFilter>>(find.byType(FilterChips<ProductFilter>));
    expect(chips.selected, ProductFilter.low);
    for (final p in low) {
      expect(find.text(p.name), findsOneWidget, reason: '${p.name} needs restock');
    }
    expect(find.text('ရေသန့် 1L'), findsNothing, reason: 'water has plenty');
    for (final p in presets) {
      expect(find.text(p.name), findsNothing, reason: 'untracked is not low');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('untracked rows show the grey badge, never "ကုန်", and are not in the low/out filters', (tester) async {
    final (c, presets) = await boot(tester);
    await openProducts(tester, c);
    await tester.enterText(find.byType(EditableText).first, 'ပဲဆီ');
    await tester.pumpAndSettle();
    expect(find.text(untrackedStockLabel), findsNWidgets(3));
    expect(find.text('ကုန်'), findsNothing, reason: 'even the one with a sale (ledger −1)');

    for (final chip in ['Stock နည်း', 'ကုန်သွားပြီ']) {
      await tester.tap(find.textContaining(chip));
      await tester.pumpAndSettle();
      for (final p in presets) {
        expect(find.text(p.name), findsNothing, reason: '$chip must exclude ${p.name}');
      }
    }
  });

  Future<void> enterQty(WidgetTester tester, List<String> keys) async {
    expect(find.text('Stock ဖြည့်မယ်'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    for (final k in keys) {
      await tester.tap(find.descendant(of: sheet, matching: find.text(k)).first);
      await tester.pump();
    }
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
  }

  testWidgets('"Stock မမှတ်ရသေး" filter: the first count starts tracking, even after earlier sales', (tester) async {
    final (c, presets) = await boot(tester);
    await openProducts(tester, c, filter: ProductFilter.untracked.name);
    for (final p in presets) {
      expect(find.text(p.name), findsOneWidget);
    }
    expect(find.text('ရေသန့် 1L'), findsNothing);

    // presets.first was sold once before tracking (ledger −1): counting 20 means 20 on hand.
    final target = presets.first;
    await tester.tap(find.text(target.name));
    await tester.pumpAndSettle();
    await enterQty(tester, ['2', '0']);

    final uow = c.read(unitOfWorkProvider) as FakeUnitOfWork;
    expect(uow.kinds.last, UnitKind.stockAdjust);
    final m = c.read(fakeDatabaseProvider).stock.last;
    expect((m.productId, m.type, m.qtyMilli), (target.id, StockMovementType.adjustment, Qty.units(21)));
    ProductView v() => c.read(productsProvider).requireValue.firstWhere((p) => p.id == target.id);
    expect((v().stockMilli, v().isUntracked), (Qty.units(20), false));
    expect(find.text(target.name), findsNothing, reason: 'it left the untracked filter');
    expect(find.text('Stock မမှတ်ရသေး (2)'), findsOneWidget);

    // Tracked now: the next delivery is a plain restock.
    await openProducts(tester, c);
    await tester.tap(find.text(target.name));
    await tester.pumpAndSettle();
    await enterQty(tester, ['5']);
    expect(uow.kinds.last, UnitKind.restock);
    expect(v().stockMilli, Qty.units(25));
  });

  testWidgets('POS tile: untracked shows the grey label, not a red low count', (tester) async {
    final (c, presets) = await boot(tester, n: 1);
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, presets.single.name);
    await tester.pumpAndSettle();
    final tile = tester.widget<ProductTile>(find.byType(ProductTile));
    expect((tile.stockLabel, tile.stockLow), (untrackedStockLabel, false));
    expect(tester.takeException(), isNull);
  });
}
