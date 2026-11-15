// QA round 12 — d8cb91e (BUG-35), adversarial, on the real local database (Drift): the 7-day chart for a week where only
// some days have sales (one of them voided), and a week whose only sales were all voided (or are older than 7 days).
//
// Developer hand-over: "if the week's max is 0, bars are flat (height 0), 'ရောင်းအား မရှိသေးပါ' is shown over the chart
// (key weekChartEmpty), and the semantics label says so." Bars: height = amount / max × 120; label = amount / 1000.
// The developer's m/report_empty_week_test.dart covers a new shop (no sales at all) and the seeded fake shop.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/core/widgets/money_text.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show drive, settle;

void main() {
  setUpAll(loadAppFonts);

  Future<(ProviderContainer, AppDatabase, Product)> boot(WidgetTester tester) async {
    final db = memoryDb();
    addTearDown(() => tester.runAsync(db.close));
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, seed: false, overrides: [
          syncApiProvider.overrideWithValue(FakeSyncApi()),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r12 rice', cost: 1000, price: 10000, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await drive(tester, () => c.read(productServiceProvider).create(p, initialStock: [
          restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(50)),
        ]));
    return (c, db, p);
  }

  /// A cash sale of [units] × 10,000 Ks, moved to noon (local) [daysAgo] days before today.
  Future<String> sell(WidgetTester tester, ProviderContainer c, AppDatabase db, Product p, int units, int daysAgo) async {
    final sale = await drive(tester, () => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(units),
            price: p.price, cost: p.cost),
        ], method: PaymentMethod.cash)));
    if (daysAgo > 0) {
      final n = DateTime.now();
      final at = DateTime(n.year, n.month, n.day - daysAgo, 12).toUtc();
      await tester.runAsync(() => (db.update(db.sales)..where((s) => s.id.equals(sale.id))).write(SalesCompanion(createdAt: Value(at))));
    }
    return sale.id;
  }

  List<String> errors(WidgetTester tester) => [
        for (Object? e = tester.takeException(); e != null; e = tester.takeException()) e.toString().split('\n').first,
      ];

  Finder chart() => find.bySemanticsLabel(RegExp('^နောက်ဆုံး ၇ ရက်'));

  /// Bar heights, oldest day first (today last).
  List<double> bars(WidgetTester tester) => [
        for (final b in tester.widgetList<Container>(find.descendant(of: chart(), matching: find.byType(Container))))
          if (b.decoration != null && b.constraints != null) b.constraints!.maxHeight,
      ];

  /// The number above each bar (thousands), oldest day first.
  List<String> labels(WidgetTester tester) => [
        for (final col in tester.widgetList<Column>(find.descendant(of: chart(), matching: find.byType(Column))))
          if (col.children.length == 5 && col.children.first is Text) (col.children.first as Text).data!,
      ];

  // ================================================================ TC-RPT-NEW-2 some days with sales
  testWidgets('TC-RPT-NEW-2 a week where only some days have sales (3 days ago 2 × 10,000; 2 days ago 6 × 10,000 VOIDED; '
      'today 4 × 10,000): no layout error, no empty message, bars [0,0,0,60,0,0,120], labels [0,0,0,20,0,0,40], the '
      'voided day is flat, "7 ရက်" total 60,000 Ks / 2 ကြိမ်, semantics names today\'s peak', (tester) async {
    final (c, db, p) = await boot(tester);
    await sell(tester, c, db, p, 2, 3);
    final voided = await sell(tester, c, db, p, 6, 2);
    await sell(tester, c, db, p, 4, 0);
    await drive(tester, () => c.read(voidSaleServiceProvider).setVoided(voided, true));
    c.read(appRouterProvider).go(Routes.reports);
    await settle(tester);

    expect(errors(tester), isEmpty);
    expect(find.byKey(const ValueKey('weekChartEmpty')), findsNothing);
    expect(find.text('ရောင်းအား မရှိသေးပါ'), findsNothing);
    expect(bars(tester), [0, 0, 0, 60, 0, 0, 120]);
    expect(labels(tester), ['0', '0', '0', '20', '0', '0', '40']);
    expect(tester.widget<MoneyText>(find.byType(MoneyText).first).amount, 60000);
    expect(find.text('2 ကြိမ်'), findsOneWidget);
    final label = tester.getSemantics(chart()).label;
    // ignore: avoid_print
    print('TC-RPT-NEW-2 semantics: $label');
    expect(label, contains('40K'));
    await tester.pump(const Duration(seconds: 3)); // the sync debounce after the last unit
    await settle(tester);
  });

  // ================================================================ TC-RPT-NEW-3 every sale voided / older than 7 days
  testWidgets('TC-RPT-NEW-3 a week whose sales were all voided (plus one sale 8 days ago): no layout error, the empty '
      'message, 7 flat bars labelled "0", total 0 Ks / 0 ကြိမ်, on every period tab; after one new sale the message goes',
      (tester) async {
    final (c, db, p) = await boot(tester);
    await sell(tester, c, db, p, 3, 8); // outside the 7 days
    for (final id in [await sell(tester, c, db, p, 2, 1), await sell(tester, c, db, p, 1, 0)]) {
      await drive(tester, () => c.read(voidSaleServiceProvider).setVoided(id, true));
    }
    c.read(appRouterProvider).go(Routes.reports);
    await settle(tester);

    for (final tab in ['ဒီနေ့', 'ဒီလ', 'ဒီအပတ်']) {
      await tester.tap(find.text(tab).first);
      await settle(tester);
      expect(errors(tester), isEmpty, reason: tab);
      expect(find.byKey(const ValueKey('weekChartEmpty')), findsOneWidget, reason: tab);
      expect(bars(tester), List.filled(7, 0.0), reason: tab);
      expect(labels(tester), List.filled(7, '0'), reason: tab);
      expect(tester.getSemantics(chart()).label, contains('ရောင်းအား မရှိသေးပါ'), reason: tab);
    }
    expect(tester.widget<MoneyText>(find.byType(MoneyText).first).amount, 0);
    expect(find.text('0 ကြိမ်'), findsOneWidget);

    await sell(tester, c, db, p, 1, 0);
    await settle(tester);
    expect(errors(tester), isEmpty);
    expect(find.byKey(const ValueKey('weekChartEmpty')), findsNothing, reason: 'the first real sale replaces the message');
    expect(bars(tester), [0, 0, 0, 0, 0, 0, 120]);
    await tester.pump(const Duration(seconds: 3)); // the sync debounce after the last unit
    await settle(tester);
  });

  // ================================================================ TC-RPT-NEW-4 screen-reader label when today is the peak
  testWidgets('TC-RPT-NEW-4 the chart\'s screen-reader label when TODAY is the highest day reads "… အမြင့်ဆုံးက ယနေ့ 40K" '
      '(not "ယနေ့နေ့"); another weekday as the peak keeps "<weekday>နေ့"', (tester) async {
    final (c, db, p) = await boot(tester);
    await sell(tester, c, db, p, 4, 0);
    c.read(appRouterProvider).go(Routes.reports);
    await settle(tester);
    final todayPeak = tester.getSemantics(chart()).label;
    await sell(tester, c, db, p, 9, 2);
    await settle(tester);
    final otherPeak = tester.getSemantics(chart()).label;
    // ignore: avoid_print
    print('TC-RPT-NEW-4 labels: today peak="${todayPeak.split('\n').last}" other peak="${otherPeak.split('\n').last}"');
    expect(otherPeak, matches(RegExp('အမြင့်ဆုံးက \\S+နေ့ 90K')));
    expect(todayPeak, isNot(contains('ယနေ့နေ့')), reason: '"ယနေ့" (today) + "နေ့" (day) is doubled');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
  });
}
