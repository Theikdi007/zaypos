// BUG-53: a template's sample cost / price are placeholder hints, never saved
// values. Empty price on a new product = 0 → POS asks for it at the first
// sale. Empty cost = unknown: profit shows "အရင်းမသိ" and those lines are left
// out of profit totals, with a note saying how many.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/shop_template.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/money_format.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/reports/domain/report_builder.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

final _templates = [for (final t in ShopTemplate.all) if (!t.soon) t];

Future<ProviderContainer> _boot(WidgetTester tester, String template) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [...fakeRepositoryOverrides, initialLimitsProvider.overrideWithValue(bundledLimits())],
  );
  addTearDown(c.dispose);
  c.read(shopTemplateProvider.notifier).select(template);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
  await tester.pumpAndSettle();
  c.read(appRouterProvider).go(Routes.addProduct);
  await tester.pumpAndSettle();
  return c;
}

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
String _text(WidgetTester t, String key) => t.widget<EditableText>(_field(key)).controller.text;

Future<Product> _save(WidgetTester tester, ProviderContainer c, String name, {String? price, String? cost}) async {
  await tester.enterText(_field('productName'), name);
  if (price != null) await tester.enterText(_field('price'), price);
  if (cost != null) await tester.enterText(_field('cost'), cost);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('သိမ်းမယ်').last);
  await tester.tap(find.text('သိမ်းမယ်').last);
  await tester.pumpAndSettle();
  final p = c.read(fakeDatabaseProvider).products.where((x) => x.name == name).firstOrNull;
  expect(p, isNotNull, reason: 'saved');
  return p!;
}

SaleLine _line(int price, int? cost, {int qty = 1000}) => SaleLine(
      id: 'l$price$cost',
      tenantId: 't',
      saleId: 's',
      name: 'x',
      qtyMilli: qty,
      price: price,
      costSnapshot: cost,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

void main() {
  setUpAll(loadAppFonts);

  for (final t in _templates) {
    group('template ${t.id}', () {
      testWidgets('cost and price open EMPTY; the sample is only placeholder text', (tester) async {
        await _boot(tester, t.id);
        expect(_text(tester, 'cost'), isEmpty);
        expect(_text(tester, 'price'), isEmpty);
        if (t.sampleCost > 0) expect(find.text('ဥပမာ ${t.sampleCost}'), findsOneWidget);
        if (t.samplePrice > 0) expect(find.text('ဥပမာ ${t.samplePrice}'), findsOneWidget);
        expect(find.byKey(const ValueKey('priceLaterNote')), findsOneWidget);
      });

      testWidgets('only a name typed → saved with cost unknown (null) and price 0 (POS asks)', (tester) async {
        final c = await _boot(tester, t.id);
        final p = await _save(tester, c, 'BUG53 ${t.id} name only');
        expect((p.cost, p.price), (null, 0), reason: 'never the sample ${t.sampleCost} / ${t.samplePrice}');
        // price 0 = ProductView.needsPrice: POS asks for it at the first sale (needs_price_test.dart).
      });

      testWidgets('name + price typed → price saved, cost stays unknown; the margin box says အရင်းမသိ', (tester) async {
        final c = await _boot(tester, t.id);
        await tester.enterText(_field('price'), '1000');
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byKey(const ValueKey('costUnknown')), matching: find.text(costUnknownLabel)),
            findsOneWidget);
        final p = await _save(tester, c, 'BUG53 ${t.id} price only');
        expect((p.cost, p.price), (null, 1000));
      });

      testWidgets('typed cost and price are saved as typed', (tester) async {
        final c = await _boot(tester, t.id);
        final p = await _save(tester, c, 'BUG53 ${t.id} both', price: '1000', cost: '700');
        expect((p.cost, p.price), (700, 1000));
      });

      testWidgets('BUG-61: a typed 0 cost is a real zero: saved as 0, the margin box shows the whole price as profit',
          (tester) async {
        final c = await _boot(tester, t.id);
        await tester.enterText(_field('price'), '5000');
        await tester.enterText(_field('cost'), '0');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('costUnknown')), findsNothing);
        expect(tester.widget<Text>(find.byKey(const ValueKey('margin'))).data, '+${formatKs(5000)}',
            reason: 'no "%" over a zero cost');
        final p = await _save(tester, c, 'BUG61 ${t.id} zero', price: '5000', cost: '0');
        expect((p.cost, p.price), (0, 5000));
      });
    });
  }

  group('profit with unknown costs', () {
    test('a line with no cost (null) is left out of profit and counted; a typed 0 is all profit (BUG-61)', () {
      expect(_line(600, 450).costKnown, isTrue);
      expect(_line(600, null).costKnown, isFalse);
      expect(_line(600, null).profit, 0, reason: 'not 600: an unknown cost is not a zero cost');
      expect((_line(600, 0).costKnown, _line(600, 0).profit), (true, 600), reason: 'a service that costs nothing');
      final s = Sale(
        id: 's',
        tenantId: 't',
        no: 'A-1',
        method: PaymentMethod.cash,
        lines: [_line(600, 450, qty: 2000), _line(1000, null)],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      expect(s.profit, 300);
      expect(s.unknownCostLines, 1);
    });

    test('report totals: known lines only, the count of unknown ones, and "unknown" when none is known', () {
      Sale sale(String id, List<SaleLine> lines) => Sale(
            id: id,
            tenantId: 't',
            no: id,
            method: PaymentMethod.cash,
            lines: lines,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
      final mixed = ReportBuilder.build([
        sale('a', [_line(600, 450)]),
        sale('b', [_line(1000, null), _line(500, null)]),
      ], const {}, ReportPeriod.today).summary;
      expect((mixed.sales, mixed.profit, mixed.unknownCostLines, mixed.profitUnknown), (2100, 150, 2, false));
      expect(formatProfit(mixed.profit, unknown: mixed.profitUnknown), '150 Ks');
      expect(unknownCostNote(mixed.unknownCostLines), 'အရင်းမသိ 2 ခု မပါ');

      final none = ReportBuilder.build([sale('c', [_line(1000, null)])], const {}, ReportPeriod.today).summary;
      expect((none.profit, none.profitUnknown), (0, true));
      expect(formatProfit(none.profit, unknown: none.profitUnknown), costUnknownLabel);

      final allKnown = ReportBuilder.build([sale('d', [_line(1000, 800)])], const {}, ReportPeriod.today).summary;
      expect((allKnown.unknownCostLines, unknownCostNote(allKnown.unknownCostLines)), (0, null));
    });

    testWidgets('dashboard and Reports show the note after a sale of a product with no cost', (tester) async {
      final c = await _boot(tester, 'grocery');
      c.read(appRouterProvider).go(Routes.dashboard);
      await tester.pumpAndSettle();
      // One known-cost line and one unknown-cost line, sold today.
      await tester.runAsync(() => sell(c, [
            draft(name: 'known', price: 600, cost: 450),
            draft(name: 'unknown', price: 1000, cost: null, qtyMilli: Qty.units(1)),
          ]));
      await tester.pumpAndSettle();
      expect(find.text('အရင်းမသိ 1 ခု မပါ'), findsWidgets);
      c.read(appRouterProvider).go(Routes.reports);
      await tester.pumpAndSettle();
      expect(find.text('အရင်းမသိ 1 ခု မပါ'), findsOneWidget);
    });
  });
}
