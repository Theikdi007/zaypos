// QA round 2 — screens of the BUG-1 / BUG-2 / BUG-3 / BUG-4 / BUG-7 fixes (widget tests on the app's
// screens; fake repositories with the design's sample data, no network).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, {String? template, double height = 1400}) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    if (template != null) c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  List<UnitKind> kinds(ProviderContainer c) => (c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds;
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  String textOf(Finder f) => editable(f).controller.text;

  Product newProduct(ProviderContainer c, String name, {int lowAlertMilli = 5000, String unit = '', int? warranty, int? expiryDays}) {
    final t = DateTime.utc(2026, 10, 1);
    return Product(
      id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
      tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t, lowAlertMilli: lowAlertMilli, unit: unit,
      warrantyMonths: warranty, expiryAlertDays: expiryDays,
    );
  }

  Future<void> openProducts(WidgetTester tester, ProviderContainer c, String search) async {
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, search);
    await tester.pumpAndSettle();
  }

  Future<void> keys(WidgetTester tester, List<String> ks) async {
    for (final k in ks) {
      await tester.tap(inSheet(find.text(k)).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapInPos(WidgetTester tester, ProviderContainer c, String name) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(EditableText).first, name);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> checkoutCash(WidgetTester tester) async {
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
  }

  int stockWhere(ProviderContainer c, bool Function(StockMovement) f) =>
      db(c).stock.where((m) => m.deletedAt == null && f(m)).fold(0, (a, m) => a + m.qtyMilli);

  // ================================================================ TC-PROD-NEW-3 edit product, every template
  group('TC-PROD-NEW-3 edit a saved product (tap the row) — every template', () {
    for (final template in ['grocery', 'pharmacy', 'phone', 'fashion', 'hardware', 'service', 'other']) {
      testWidgets('$template: form prefilled, "ပစ္စည်း ပြင်မယ်", name/price/cost saved as ONE upsertProduct, '
          'createdAt + module rows + stock untouched', (tester) async {
        final c = await boot(tester, template: template);
        final f = c.read(tenantFeaturesProvider);
        final tid = c.read(tenantIdProvider);
        final t = DateTime.utc(2026, 10, 1);
        final p = newProduct(c, 'QA $template ပစ္စည်း',
            lowAlertMilli: f.decimalQty ? 2500 : 5000,
            unit: f.decimalQty ? 'ပေ' : '',
            warranty: f.serialWarranty ? 12 : null,
            expiryDays: f.expiryBatch ? 60 : null);
        final variant = ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: 'M', color: 'အနက်', createdAt: t, updatedAt: t);
        final batch = ProductBatch(id: newId(), tenantId: tid, productId: p.id, batchNo: 'QB1', qtyMilli: 0,
            expiryDate: DateTime.utc(2027, 6, 30), createdAt: t, updatedAt: t);
        final serial = ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: '356984102231457',
            status: SerialStatus.inStock, createdAt: t, updatedAt: t);
        await c.read(productServiceProvider).create(p,
            variants: f.variants ? [variant] : const [],
            batches: f.expiryBatch ? [batch] : const [],
            serials: f.serialWarranty ? [serial] : const [],
            initialStock: f.stock
                ? [
                    restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(4),
                        variantId: f.variants ? variant.id : null, batchId: f.expiryBatch ? batch.id : null, note: 'initial'),
                  ]
                : const []);
        final moves0 = db(c).stock.length;
        final modules0 = (db(c).variants.length, db(c).batches.length, db(c).serials.length);

        await openProducts(tester, c, p.name);
        await tester.tap(find.text(p.name).last);
        await tester.pumpAndSettle();

        expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget, reason: 'edit title');
        expect(textOf(field('productName')), p.name);
        expect(textOf(field('price')), '600');
        if (f.stock) expect(textOf(field('lowAlert')), f.decimalQty ? '2.5' : '5');
        // Stock / IMEIs / variants / batches are not edited here.
        expect(find.byKey(const ValueKey('stockQty')), findsNothing);
        expect(find.byKey(const ValueKey('imei')), findsNothing);
        expect(find.byKey(const ValueKey('batchNo')), findsNothing);
        expect(find.byKey(const ValueKey('M · အနက်')), findsNothing);

        await tester.enterText(field('productName'), 'QA $template ပြင်ပြီး');
        await tester.enterText(field('price'), '750');
        if (f.stock && f.decimalQty) await tester.enterText(field('lowAlert'), '0.75');
        await tester.pumpAndSettle();
        await tester.tap(find.text('သိမ်းမယ်').last);
        await tester.pumpAndSettle();

        final after = db(c).products.firstWhere((x) => x.id == p.id);
        expect((after.name, after.price, after.cost, after.createdAt), ('QA $template ပြင်ပြီး', 750, 400, t));
        expect(after.updatedAt.isAfter(t), isTrue, reason: 'LWW: a newer updatedAt');
        expect(kinds(c).last, UnitKind.upsertProduct);
        expect(db(c).stock.length, moves0, reason: 'editing never writes stock');
        expect((db(c).variants.length, db(c).batches.length, db(c).serials.length), modules0);
        expect(after.warrantyMonths, f.serialWarranty ? 12 : null, reason: 'phone: warranty kept');
        expect(after.expiryAlertDays, f.expiryBatch ? 60 : null, reason: 'pharmacy: expiry alert kept');
        expect(after.unit, p.unit);
        if (f.stock && f.decimalQty) expect(after.lowAlertMilli, 750, reason: 'hardware: decimal low alert');
        expect(find.text('ပစ္စည်း ပြင်မယ်'), findsNothing, reason: 'back on the list');
      });
    }

    testWidgets('grocery preset without a price: the edit form refuses an empty price, then saves one', (tester) async {
      final c = await boot(tester, template: 'grocery');
      final p = newProduct(c, 'QA preset').copyWith(price: 0);
      await c.read(productServiceProvider).importAll([p]);
      final n = kinds(c).length;
      await openProducts(tester, c, p.name);
      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      expect(textOf(field('price')), '');
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(find.text('ရောင်းဈေး ထည့်ပါ။'), findsOneWidget);
      expect(kinds(c).length, n, reason: 'nothing saved');
      await tester.enterText(field('price'), '900');
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(db(c).products.firstWhere((x) => x.id == p.id).price, 900);
    });
  });

  // ================================================================ TC-PROD-NEW-4 restock from the stock badge
  group('TC-PROD-NEW-4 "Stock ဖြည့်မယ်" from the stock badge', () {
    testWidgets('grocery: the badge opens the sheet (whole units, no "."), +5 is ONE restock unit; the row opens edit',
        (tester) async {
      final c = await boot(tester);
      await openProducts(tester, c, 'ရေသန့် 1L');
      final before = stockWhere(c, (m) => m.productId == SeedIds.water);
      await tester.tap(find.byKey(ValueKey('restock-${SeedIds.water}')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Stock ဖြည့်မယ်')), findsOneWidget);
      expect(inSheet(find.text('.')), findsNothing, reason: 'decimalQty is off');
      await keys(tester, ['5']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(stockWhere(c, (m) => m.productId == SeedIds.water), before + Qty.units(5));
      expect(kinds(c).last, UnitKind.restock);
      final mv = db(c).stock.last;
      expect((mv.type, mv.qtyMilli), (StockMovementType.restock, Qty.units(5)));

      await tester.tap(find.text('ရေသန့် 1L').last);
      await tester.pumpAndSettle();
      expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget, reason: 'the row itself is edit, not restock');
    });

    testWidgets('hardware: 2.5 ပေ received → +2,500 milli', (tester) async {
      final c = await boot(tester, template: 'hardware');
      final p = newProduct(c, 'QA ကြိုး', unit: 'ပေ');
      await c.read(productServiceProvider).create(p, initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(10), note: 'initial'),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['2', '.', '5']);
      expect(find.byKey(const ValueKey('qtySheetValue')), findsOneWidget);
      expect((tester.widget<Text>(find.byKey(const ValueKey('qtySheetValue')))).data, '2.5 ပေ');
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(10) + 2500);
    });
  });

  // ================================================================ TC-PROD-NEW-5 restock of IMEI / batch / variant products
  group('TC-PROD-NEW-5 goods received for an IMEI / batch / size-colour product can be sold correctly', () {
    testWidgets('phone: sell the only IMEI, receive 1 more through "Stock ဖြည့်မယ်" → the new phone can be sold',
        (tester) async {
      final c = await boot(tester, template: 'phone');
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA Redmi 13');
      final s1 = ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: '111111111111111',
          status: SerialStatus.inStock, createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, serials: [s1], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(1), note: 'initial'),
      ]);
      await sell(c, [(productId: p.id, variantId: null, batchId: null, serialId: s1.id, name: p.name, qtyMilli: 1000, price: 600, cost: 400)]);

      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      final asksImei = find.byKey(const ValueKey('imei')).evaluate().isNotEmpty || inSheet(find.textContaining('IMEI')).evaluate().isNotEmpty;
      await keys(tester, ['1']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(1), reason: 'stock says 1 phone on hand');

      await tapInPos(tester, c, p.name);
      final blocked = find.text('ရောင်းစရာ IMEI မကျန်တော့ပါ').evaluate().isNotEmpty;
      expect((asksImei, blocked), (true, false),
          reason: 'restock asked for no IMEI, and POS refuses to sell the phone that stock says is on hand');
    });

    testWidgets('pharmacy: goods received for a batch product belong to a batch (no. + expiry)', (tester) async {
      final c = await boot(tester, template: 'pharmacy');
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA Amoxicillin');
      final b1 = ProductBatch(id: newId(), tenantId: tid, productId: p.id, batchNo: 'B1', qtyMilli: 0,
          expiryDate: DateTime.utc(2027, 1, 31), createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, batchId: b1.id, qtyMilli: Qty.units(2), note: 'initial'),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['1', '0']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      final received = db(c).stock.last;
      expect(received.qtyMilli, Qty.units(10));
      expect(received.batchId, isNotNull,
          reason: 'the 10 received have no batch / expiry: batch stock (B1 = 2) no longer matches product stock (12)');
    });

    testWidgets('fashion: goods received for a size-colour product belong to a variant', (tester) async {
      final c = await boot(tester, template: 'fashion');
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA ဂျင်း');
      final v = ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: '30', color: 'အပြာ', createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, variants: [v], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, variantId: v.id, qtyMilli: Qty.units(1), note: 'initial'),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['3']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(db(c).stock.last.variantId, isNotNull,
          reason: 'the 3 received belong to no size/colour: POS asks for a variant whose stock never grows');
    });
  });

  // ================================================================ TC-POS-NEW-4 choose IMEI / variant / batch at POS
  group('TC-POS-NEW-4 POS asks which IMEI / size-colour / batch', () {
    testWidgets('fashion: the cashier picks L · အဖြူ (not the first) → only that variant drops', (tester) async {
      final c = await boot(tester, template: 'fashion', height: 844);
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA ရှပ် v2');
      final m = ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: 'M', color: 'အနက်', createdAt: t, updatedAt: t);
      final l = ProductVariant(id: newId(), tenantId: tid, productId: p.id, size: 'L', color: 'အဖြူ', createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, variants: [m, l], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, variantId: m.id, qtyMilli: Qty.units(3), note: 'initial'),
        restockMovement(tenantId: tid, productId: p.id, variantId: l.id, qtyMilli: Qty.units(2), note: 'initial'),
      ]);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Size / အရောင် လဲ?'), findsOneWidget);
      expect(inSheet(find.text('ကျန် 3')), findsOneWidget);
      expect(inSheet(find.text('ကျန် 2')), findsOneWidget);
      await tester.tap(inSheet(find.textContaining('L')).first);
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.variantId, l.id);
      await checkoutCash(tester);
      expect(stockWhere(c, (x) => x.variantId == l.id), Qty.units(1));
      expect(stockWhere(c, (x) => x.variantId == m.id), Qty.units(3));
      final line = db(c).sales.expand((s) => s.lines).firstWhere((x) => x.productId == p.id);
      expect(line.variantId, l.id);
      expect(line.name, contains('L · အဖြူ'));
    });

    testWidgets('pharmacy: earliest expiry first, undated last, empty batches hidden; picked batch drops', (tester) async {
      final c = await boot(tester, template: 'pharmacy', height: 844);
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA Cetirizine');
      ProductBatch b(String no, DateTime? exp) => ProductBatch(id: newId(), tenantId: tid, productId: p.id, batchNo: no,
          qtyMilli: 0, expiryDate: exp, createdAt: t, updatedAt: t);
      final late = b('LATE28', DateTime.utc(2028, 3, 1));
      final undated = b('NODATE', null);
      final early = b('EARLY27', DateTime.utc(2027, 2, 1));
      final empty = b('EMPTY26', DateTime.utc(2026, 12, 31));
      StockMovement into(ProductBatch x, int u) =>
          restockMovement(tenantId: tid, productId: p.id, batchId: x.id, qtyMilli: Qty.units(u), note: 'initial');
      await c.read(productServiceProvider).create(p, batches: [late, undated, early, empty],
          initialStock: [into(late, 5), into(undated, 5), into(early, 5)]);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget);
      double y(String s) => tester.getTopLeft(inSheet(find.textContaining(s))).dy;
      expect(y('EARLY27'), lessThan(y('LATE28')));
      expect(y('LATE28'), lessThan(y('NODATE')));
      expect(inSheet(find.textContaining('EMPTY26')), findsNothing, reason: 'no stock left in it');
      await tester.tap(inSheet(find.textContaining('EARLY27')));
      await tester.pumpAndSettle();
      await checkoutCash(tester);
      expect(stockWhere(c, (x) => x.batchId == early.id), Qty.units(4));
      expect(stockWhere(c, (x) => x.batchId == late.id), Qty.units(5));
    });

    testWidgets('phone: after selling IMEI A (full checkout) the next sale offers only IMEI B', (tester) async {
      final c = await boot(tester, template: 'phone', height: 844);
      final tid = c.read(tenantIdProvider);
      final t = nowUtc();
      final p = newProduct(c, 'QA Galaxy v2');
      ProductSerial s(String imei) => ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: imei,
          status: SerialStatus.inStock, createdAt: t, updatedAt: t);
      final a = s('356984102231457');
      final b = s('356984102231465');
      await c.read(productServiceProvider).create(p, serials: [a, b], initialStock: [
        restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(2), note: 'initial'),
      ]);
      await tapInPos(tester, c, p.name);
      await tester.tap(inSheet(find.text(a.serial)));
      await tester.pumpAndSettle();
      await checkoutCash(tester);
      final soldA = db(c).serials.firstWhere((x) => x.id == a.id);
      final line = db(c).sales.expand((x) => x.lines).firstWhere((x) => x.serialId == a.id);
      expect((soldA.status, soldA.saleLineId), (SerialStatus.sold, line.id));

      await tapInPos(tester, c, p.name);
      expect(inSheet(find.text(a.serial)), findsNothing, reason: 'sold');
      expect(inSheet(find.text(b.serial)), findsOneWidget);
    });
  });

  // ================================================================ TC-POS-NEW-3 quantity keypad
  group('TC-POS-NEW-3 checkout quantity keypad', () {
    testWidgets('hardware: tap qty → "." → 2.5 → line 1,500 Ks; 4th decimal ignored; the sale stores 2,500 milli',
        (tester) async {
      final c = await boot(tester, template: 'hardware', height: 844);
      final water = db(c).products.firstWhere((p) => p.id == SeedIds.water); // 600 Ks
      final stock0 = stockWhere(c, (m) => m.productId == water.id);
      c.read(cartProvider.notifier).addProduct(water);
      c.read(appRouterProvider).go(Routes.checkout);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('qty-${water.id}')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('.')), findsOneWidget);
      await keys(tester, ['0', '.', '1', '2', '3', '4']);
      expect(tester.widget<Text>(find.byKey(const ValueKey('qtySheetValue'))).data, startsWith('0.123 '),
          reason: 'max 3 decimal places');
      await keys(tester, ['⌫', '⌫', '⌫', '⌫', '⌫']);
      await keys(tester, ['2', '.', '5']);
      await tester.tap(inSheet(find.text('ပြောင်းမယ်')));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.qtyMilli, 2500);
      expect(find.textContaining('1,500'), findsWidgets, reason: '600 × 2.5');

      final ids0 = {for (final s in db(c).sales) s.id};
      await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
      await tester.pumpAndSettle();
      final sale = db(c).sales.singleWhere((s) => !ids0.contains(s.id));
      expect((sale.lines.single.qtyMilli, sale.total), (2500, 1500));
      expect(stockWhere(c, (m) => m.productId == water.id), stock0 - 2500);
    });

    testWidgets('grocery (decimal off): no "." key; typing 3 sets 3; an empty / 0 entry cannot be confirmed', (tester) async {
      final c = await boot(tester, height: 844);
      final water = db(c).products.firstWhere((p) => p.id == SeedIds.water);
      c.read(cartProvider.notifier).addProduct(water);
      c.read(appRouterProvider).go(Routes.checkout);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('qty-${water.id}')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('.')), findsNothing);
      await keys(tester, ['⌫']);
      await tester.tap(inSheet(find.text('ပြောင်းမယ်')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget, reason: '0 cannot be confirmed (sheet stays open)');
      expect(c.read(cartProvider).lines.single.qtyMilli, Qty.units(1), reason: 'unchanged');
      await keys(tester, ['3']);
      await tester.tap(inSheet(find.text('ပြောင်းမယ်')));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.qtyMilli, Qty.units(3));
    });
  });

  // ================================================================ TC-DEBT-NEW-3 reverse a wrong payment
  testWidgets('TC-DEBT-NEW-3 tap a payment → "ပြန်ပယ်မယ်" → +amount adjustment, payment kept & marked; cancel does nothing; '
      'a reversed payment cannot be reversed again', (tester) async {
    final c = await boot(tester);
    final tid = c.read(tenantIdProvider);
    int balance() => debtBalance(db(c).debt.where((e) => e.customerId == SeedIds.aungKyaw));
    final owed0 = balance();
    final pay = await c.read(customerServiceProvider)
        .recordPayment(tenantId: tid, customerId: SeedIds.aungKyaw, amount: 7350, method: PaymentMethod.kbz);
    expect(balance(), owed0 - 7350);
    c.read(appRouterProvider).go(Routes.customer(SeedIds.aungKyaw));
    await tester.pumpAndSettle();

    await tester.tap(find.text('− 7,350'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကို ပြန်ပယ်မလား'), findsOneWidget);
    await tester.tap(find.text('မလုပ်တော့ပါ'));
    await tester.pumpAndSettle();
    expect(balance(), owed0 - 7350, reason: 'cancel = nothing');

    final units0 = kinds(c).length;
    await tester.tap(find.text('− 7,350'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပြန်ပယ်မယ်'));
    await tester.pumpAndSettle();
    expect(balance(), owed0, reason: 'balance back to before the wrong payment');
    expect(kinds(c).sublist(units0), [UnitKind.payDebt], reason: 'ONE payDebt unit');
    final rev = db(c).debt.singleWhere((e) => e.id == paymentReversalId(pay.id));
    expect((rev.type, rev.amount), (DebtEntryType.adjustment, 7350));
    expect(db(c).debt.where((e) => e.id == pay.id && e.deletedAt == null), hasLength(1), reason: 'never deleted');
    expect(find.textContaining('ပြန်ပယ်ပြီး'), findsOneWidget);

    await tester.tap(find.text('− 7,350'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကို ပြန်ပယ်မလား'), findsNothing, reason: 'already reversed');
    expect(balance(), owed0);
  });

  // ================================================================ TC-DEBT-NEW-5 credit-limit warning (boundaries)
  group('TC-DEBT-NEW-5 checkout credit-limit warning', () {
    Future<ProviderContainer> creditCheckout(WidgetTester tester, int? limit) async {
      final c = await boot(tester, height: 844);
      final i = db(c).customers.indexWhere((x) => x.id == SeedIds.thanHtun); // owes 96,000
      db(c).customers[i] = db(c).customers[i].copyWith(creditLimit: () => limit);
      db(c).touch({FakeTable.customers});
      final water = db(c).products.firstWhere((p) => p.id == SeedIds.water);
      for (var k = 0; k < 40; k++) {
        c.read(cartProvider.notifier).addProduct(water); // 24,000
      }
      c.read(appRouterProvider).go(Routes.checkout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('အကြွေး'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ရွေးရန်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ဦးသန်းထွန်း'));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('exactly at the limit (96,000 + 24,000 = 120,000): no warning', (tester) async {
      await creditCheckout(tester, 120000);
      expect(find.byKey(const ValueKey('creditLimitWarning')), findsNothing);
    });

    testWidgets('no limit: no warning', (tester) async {
      await creditCheckout(tester, null);
      expect(find.byKey(const ValueKey('creditLimitWarning')), findsNothing);
    });

    testWidgets('1 Ks over: warning with limit and balance after; it does not block — the credit sale is saved',
        (tester) async {
      final c = await creditCheckout(tester, 119999);
      final w = tester.widget<Text>(find.byKey(const ValueKey('creditLimitWarning'))).data!;
      expect(w, allOf(contains('119,999'), contains('120,000')));
      final ids0 = {for (final s in db(c).sales) s.id};
      await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
      await tester.pumpAndSettle();
      final sale = db(c).sales.singleWhere((s) => !ids0.contains(s.id));
      expect((sale.method, sale.customerId, sale.total), (PaymentMethod.debt, SeedIds.thanHtun, 24000));
    });
  });
}

/// The EditableText under [f].
EditableText editable(Finder f) => f.evaluate().single.widget as EditableText;
