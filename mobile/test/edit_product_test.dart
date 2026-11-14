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
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';

/// BUG-1: tapping a product opens the Add Product form in edit mode; saving
/// writes ONE upsertProduct unit and keeps stock untouched.
void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('tap a product → edit form prefilled → new price/cost/name saved as one upsertProduct unit',
      (tester) async {
    final c = await boot(tester);
    final db = c.read(fakeDatabaseProvider);
    final before = db.products.firstWhere((p) => p.name == 'ရေသန့် 1L');
    final stockBefore = db.stock.length;

    await tester.tap(find.text('ရေသန့် 1L'));
    await tester.pumpAndSettle();
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget);
    expect(find.text('ရောင်းဈေး (Ks)'), findsOneWidget);
    final price = find.byKey(const ValueKey('price'));
    expect(tester.widget<EditableText>(find.descendant(of: price, matching: find.byType(EditableText))).controller.text,
        '${before.price}');

    await tester.enterText(find.byKey(const ValueKey('productName')), 'ရေသန့် 1 လီတာ');
    await tester.enterText(price, '${before.price + 100}');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();

    final after = db.products.firstWhere((p) => p.id == before.id);
    expect((after.name, after.price, after.cost, after.createdAt), ('ရေသန့် 1 လီတာ', before.price + 100, before.cost, before.createdAt));
    expect(after.updatedAt.isAfter(before.updatedAt) || after.updatedAt == before.updatedAt, isTrue);
    expect((c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds.last, UnitKind.upsertProduct);
    expect(db.stock.length, stockBefore, reason: 'editing never writes stock');
    expect(find.text('ရေသန့် 1 လီတာ'), findsOneWidget, reason: 'back on the list with the new name');
  });

  test('Drift: update is ONE upsertProduct unit with the whole row; createdAt kept, stock untouched', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = DateTime.utc(2026, 1, 1);
    final p = Product(
      id: newId(), tenantId: shop.tenantId, name: 'ဆီ', cost: 900, price: 1000,
      category: 'စားသောက်ကုန်', tint: 0xFFDCFCE7, initial: 'ဆ', createdAt: t, updatedAt: t,
    );
    await c.read(productServiceProvider).create(p);
    await db.delete(db.outbox).go();

    await c.read(productServiceProvider).update(p.copyWith(name: 'ပဲဆီ', price: 1200, cost: 1000));

    final unit = (await outbox(db)).single;
    expect(unit.kind, 'upsertProduct');
    final rows = SyncStore.rowsOf(unit);
    expect(rows.keys, [WireTable.products]);
    final row = (rows[WireTable.products] as List).single as Map;
    expect((row['id'], row['name'], row['price'], row['cost']), (p.id, 'ပဲဆီ', 1200, 1000));
    expect(DateTime.parse(row['updatedAt'] as String).isAfter(t), isTrue);
    final saved = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((saved.name, saved.createdAt.toUtc()), ('ပဲဆီ', t));

    await expectLater(c.read(productServiceProvider).update(p.copyWith(price: 0)), throwsArgumentError);
    expect(await outbox(db), hasLength(1));
  });

  testWidgets('the stock badge (not the row) opens "Stock ဖြည့်မယ်"', (tester) async {
    final c = await boot(tester);
    final p = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.name == 'ရေသန့် 1L');
    await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Stock ဖြည့်မယ်'), findsOneWidget);
    expect(find.text('ရောင်းဈေး (Ks)'), findsNothing);
  });
}
