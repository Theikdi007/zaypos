import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/widgets/product_tile.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/presentation/products_screen.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';

/// A product with price 0 (e.g. from the preset catalog) is never sold silently.
void main() {
  setUpAll(loadAppFonts);

  Product unpriced(String tenantId, {String name = 'ကိုကာကိုလာ 330ml'}) {
    final t = nowUtc();
    return Product(
      id: newId(),
      tenantId: tenantId,
      name: name,
      cost: 0,
      price: 0,
      category: 'အချိုရည်',
      tint: 0xFFDBEAFE,
      initial: 'က',
      createdAt: t,
      updatedAt: t,
    );
  }

  Future<(ProviderContainer, Product)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    final p = unpriced(c.read(tenantIdProvider));
    c.read(fakeDatabaseProvider)
      ..products.add(p)
      ..touch({FakeTable.products});
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, p);
  }

  Product stored(ProviderContainer c, String id) => c.read(fakeDatabaseProvider).products.firstWhere((x) => x.id == id);

  Future<void> openPosProducts(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'ကိုကာ'); // search: only this tile
    await tester.pumpAndSettle();
  }

  testWidgets('Dashboard card counts unpriced products and opens the filtered Products list', (tester) async {
    final (c, p) = await boot(tester);
    expect(find.text('ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း ၁ ခု'), findsOneWidget);

    await tester.tap(find.text('ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း ၁ ခု'));
    await tester.pumpAndSettle();

    final screen = tester.widget<ProductsScreen>(find.byType(ProductsScreen));
    expect(screen.initialFilter, ProductFilter.noPrice);
    expect(find.text(p.name), findsOneWidget);
    expect(find.text('ရေသန့် 1L'), findsNothing, reason: 'priced products are filtered out');
    expect(find.text(NeedsPriceBadge.label), findsOneWidget);
    expect(find.text('ဈေးနှုန်းမရှိ (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no unpriced products: no Dashboard card', (tester) async {
    final (c, p) = await boot(tester);
    c.read(fakeDatabaseProvider)
      ..products.removeWhere((x) => x.id == p.id)
      ..touch({FakeTable.products});
    await tester.pumpAndSettle();
    expect(find.textContaining('ဈေးနှုန်း မထည့်ရသေးသော'), findsNothing);
  });

  testWidgets('POS: the tile shows the badge; tapping asks for the price, saves it and sells at it', (tester) async {
    final (c, p) = await boot(tester);
    await openPosProducts(tester, c);
    expect(find.descendant(of: find.byType(ProductTile), matching: find.text(NeedsPriceBadge.label)), findsOneWidget);

    // Dismissed: nothing is added, the price stays 0.
    await tester.tap(find.text(p.name));
    await tester.pumpAndSettle();
    expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsOneWidget);
    await tester.tapAt(const Offset(195, 40)); // outside the sheet
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).isEmpty, isTrue);
    expect(stored(c, p.id).price, 0);

    // Entered: saved to the product as an upsertProduct unit, used for this sale.
    await tester.tap(find.text(p.name));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    for (final k in ['1', '5', '00']) {
      await tester.tap(find.descendant(of: sheet, matching: find.text(k)).first);
      await tester.pump();
    }
    await tester.tap(find.text('သိမ်းပြီး ခြင်းထဲထည့်မယ်'));
    await tester.pumpAndSettle();

    expect(stored(c, p.id).price, 1500);
    expect((c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds.last, UnitKind.upsertProduct);
    final line = c.read(cartProvider).lines.single;
    expect((line.productId, line.price), (p.id, 1500));
    expect(find.descendant(of: find.byType(ProductTile), matching: find.text(NeedsPriceBadge.label)), findsNothing);

    // Next time it is a normal product: no question.
    await tester.tap(find.text(p.name));
    await tester.pumpAndSettle();
    expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsNothing);
    expect(c.read(cartProvider).lines.single.qtyMilli, 2000);
  });

  testWidgets('Quick Sale is unaffected (no price question)', (tester) async {
    final (c, _) = await boot(tester);
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    for (final k in ['5', '00']) {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await tester.tap(find.text('+ ခြင်းထဲထည့်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ဈေးနှုန်း ထည့်ပါ'), findsNothing);
    expect(c.read(cartProvider).lines.single.price, 500);
  });

  group('Drift', () {
    test('setPrice is ONE upsertProduct unit with the whole product row (newer updatedAt)', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final (c, shop) = await driftContainer(db, seed: false);
      addTearDown(c.dispose);
      final p = unpriced(shop.tenantId);
      await c.read(productServiceProvider).create(p);
      await db.delete(db.outbox).go();

      await c.read(productServiceProvider).setPrice(p.id, 1500);

      final unit = (await outbox(db)).single;
      expect(unit.kind, 'upsertProduct');
      final row = (SyncStore.rowsOf(unit)[WireTable.products] as List).single as Map;
      expect((row['id'], row['price'], row['name'], row['category']), (p.id, 1500, p.name, p.category));
      expect(DateTime.parse(row['updatedAt'] as String).isBefore(p.updatedAt), isFalse);
      expect((await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()).price, 1500);

      await expectLater(c.read(productServiceProvider).setPrice(p.id, 0), throwsArgumentError);
      expect(await outbox(db), hasLength(1));
    });
  });
}
