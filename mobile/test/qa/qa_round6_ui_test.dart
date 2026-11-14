// QA round 6 — re-test of BUG-22 (edit form: opening batch for stock outside batches) and BUG-23 (void of the original
// sale after a trade-in), 667a0e2, plus the edge cases next to them. Widget tests on the app's screens with the fake
// repositories (no network).
//
// Spec lines used:
// - owner item 5: "batches are required only for products with expiryAlertDays set"
// - owner decision 2: "an expiry-tracked product cannot be saved with opening stock unless a batch number (and expiry) is
//   entered"
// - owner decision 3: "an IMEI whose last status is 'sold' can be received again (new inStock row, history kept); an IMEI
//   that is 'inStock' is still refused"
// - BUG-22 fix (667a0e2): "then ONE upsertProduct unit: product + opening batch + 'opening batch' adjustments (−loose / +into
//   batch, per variant group) so batch stock = product stock"
// - BUG-23 fix (667a0e2): "voiding the original sale of a traded-in IMEI ... keeps the newer row: the old row stays sold
//   (history), no voidReturn movement for that line; un-void mirrors it"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart' show SaleLineDraft;
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import 'qa_form_helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, String template, {double height = 1000}) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  List<UnitKind> kinds(ProviderContainer c) => (c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds;
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  int stockWhere(ProviderContainer c, bool Function(StockMovement) f) =>
      db(c).stock.where((m) => m.deletedAt == null && f(m)).fold(0, (a, m) => a + m.qtyMilli);
  int productStock(ProviderContainer c, String id) => stockWhere(c, (m) => m.productId == id);

  final t0 = DateTime.utc(2026, 10, 1);
  const loose10 = 'လက်ရှိ Batch မရှိတဲ့ stock 10 ခု အတွက် Batch နံပါတ် နဲ့ သက်တမ်းကုန်ရက် ထည့်ပါ။';

  Product newProduct(ProviderContainer c, String name, {int? expiryAlertDays}) => Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0, expiryAlertDays: expiryAlertDays,
      );
  ProductSerial serial(Product p, String imei) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
  ProductBatch batch(Product p, String no, DateTime? exp) => ProductBatch(
      id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: no, qtyMilli: 0, expiryDate: exp, createdAt: t0, updatedAt: t0);
  ProductVariant variant(Product p, String size, String color) => ProductVariant(
      id: newId(), tenantId: p.tenantId, productId: p.id, size: size, color: color, createdAt: t0, updatedAt: t0);
  StockMovement into(Product p, int units, {String? batchId, String? variantId}) => restockMovement(
      tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: batchId, variantId: variantId, note: 'initial');
  SaleLineDraft line(Product p, {String? batchId, String? serialId, int units = 1}) => (
        productId: p.id, variantId: null, batchId: batchId, serialId: serialId, name: p.name, qtyMilli: Qty.units(units),
        price: 600, cost: 400,
      );
  Future<Sale> sell(ProviderContainer c, List<SaleLineDraft> lines) =>
      c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: lines, method: PaymentMethod.cash));

  Future<void> openProducts(WidgetTester tester, ProviderContainer c, String search) async {
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, search);
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester, ProviderContainer c, Product p) async {
    await openProducts(tester, c, p.name);
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget);
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
  }

  Future<void> typeBatchNo(WidgetTester tester, String no) async {
    await tester.ensureVisible(field('batchNo'));
    await tester.enterText(field('batchNo'), no);
    await tester.pumpAndSettle();
  }

  bool onForm() => find.text('ပစ္စည်း ပြင်မယ်').evaluate().isNotEmpty;

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

  // ================================================================ BUG-22 / TC-PROD-NEW-27
  group('TC-PROD-NEW-27 (BUG-22) edit form: opening batch for stock outside batches', () {
    testWidgets('plain medicine 10 loose → "ရက် ၃၀ အလို": note + batch fields; no batch no. → refused; batch no. without '
        'expiry → refused; both → ONE upsertProduct, opening batch holds 10, 0 loose, stock 10; POS then sells from it',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R6 med switch');
      await c.read(productServiceProvider).create(p, initialStock: [into(p, 10)]);
      await openEdit(tester, c, p);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsNothing, reason: 'not tracked: no note');
      await pickExpiryWarn(tester, warn30Label);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsOneWidget);
      expect(find.text('လက်ရှိ Batch မရှိတဲ့ stock 10 ခု ကို ဒီ Batch ထဲ ထည့်ပါမယ် · Batch နံပါတ် နဲ့ သက်တမ်းကုန်ရက် ထည့်ပါ'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('batchNo')), findsOneWidget);

      final n0 = kinds(c).length;
      await saveForm(tester);
      expect((onForm(), find.text(loose10).evaluate().length, kinds(c).length), (true, 1, n0), reason: 'no batch no.: refused');

      await typeBatchNo(tester, 'OPEN6');
      await saveForm(tester);
      expect((onForm(), find.text(loose10).evaluate().length, kinds(c).length), (true, 1, n0),
          reason: 'batch no. without expiry: refused (decision 2), nothing written');
      expect(db(c).products.firstWhere((x) => x.id == p.id).expiryAlertDays, isNull);
      expect(db(c).batches.where((b) => b.productId == p.id), isEmpty);

      await pickAddProductExpiry(tester, 28);
      await saveForm(tester);
      expect(onForm(), isFalse, reason: 'saved');
      expect(kinds(c).sublist(n0), [UnitKind.upsertProduct], reason: 'ONE unit');
      expect(db(c).products.firstWhere((x) => x.id == p.id).expiryAlertDays, 30);
      final b = db(c).batches.singleWhere((x) => x.productId == p.id);
      final now = DateTime.now();
      expect((b.batchNo, b.expiryDate), ('OPEN6', DateTime.utc(now.year, now.month, 28)));
      expect(stockWhere(c, (m) => m.batchId == b.id), Qty.units(10), reason: 'batch stock = product stock');
      expect(stockWhere(c, (m) => m.productId == p.id && m.batchId == null), 0, reason: 'nothing left outside batches');
      expect(productStock(c, p.id), Qty.units(10), reason: 'product stock unchanged');
      final adj = db(c).stock.where((m) => m.productId == p.id && m.note == 'opening batch').toList();
      expect(adj.map((m) => (m.type, m.qtyMilli, m.batchId)).toSet(),
          {(StockMovementType.adjustment, -Qty.units(10), null), (StockMovementType.adjustment, Qty.units(10), b.id)});

      // POS: the only batch with stock is picked; the sale takes it from OPEN6
      await tapInPos(tester, c, p.name);
      expect(c.read(cartProvider).lines.single.batchId, b.id);
      c.read(cartProvider.notifier).clear();

      // reopen the edit form: no opening batch asked any more; a price edit saves
      await openEdit(tester, c, p);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsNothing, reason: 'no loose stock left');
      final n1 = kinds(c).length;
      await tester.enterText(field('price'), '650');
      await saveForm(tester);
      expect((onForm(), kinds(c).sublist(n1).join(',')), (false, 'UnitKind.upsertProduct'));
      expect(db(c).batches.where((x) => x.productId == p.id), hasLength(1), reason: 'no second opening batch');
    });

    testWidgets('tracked medicine: batch B1 (5) + 3 loose → note says 3; batch no. "B1" and " B1 " → "ဒီ Batch ရှိပြီးသားပါ။", '
        'nothing written; "B2" → B2 holds 3, B1 stays 5, stock 8', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R6 med mixed', expiryAlertDays: 30);
      final b1 = batch(p, 'B1', DateTime.utc(2030, 1, 1));
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [into(p, 5, batchId: b1.id), into(p, 3)]);
      await openEdit(tester, c, p);
      expect(find.textContaining('လက်ရှိ Batch မရှိတဲ့ stock 3 ခု ကို'), findsOneWidget, reason: 'note counts only loose stock');
      await pickAddProductExpiry(tester, 28);
      final n0 = kinds(c).length;
      for (final no in ['B1', ' B1 ']) {
        await typeBatchNo(tester, no);
        await saveForm(tester);
        expect((onForm(), find.text('ဒီ Batch ရှိပြီးသားပါ။').evaluate().length, kinds(c).length), (true, 1, n0),
            reason: 'existing batch number "$no" refused');
      }
      await typeBatchNo(tester, 'B2');
      await saveForm(tester);
      expect(onForm(), isFalse);
      expect(kinds(c).sublist(n0), [UnitKind.upsertProduct]);
      final b2 = db(c).batches.singleWhere((x) => x.productId == p.id && x.batchNo == 'B2');
      expect((stockWhere(c, (m) => m.batchId == b1.id), stockWhere(c, (m) => m.batchId == b2.id)), (Qty.units(5), Qty.units(3)));
      expect(stockWhere(c, (m) => m.productId == p.id && m.batchId == null), 0);
      expect(productStock(c, p.id), Qty.units(8));
    });

    testWidgets('fashion + Batch feature: sizes M (3) / L (2) loose → "ရက် ၃၀ အလို" + batch → per size: M 3 and L 2 '
        'unchanged, batch 5, product 5, 0 loose', (tester) async {
      final c = await boot(tester, 'fashion', height: 1400);
      c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.expiryBatch, true);
      await tester.pumpAndSettle();
      final p = newProduct(c, 'QA R6 shirt');
      final m = variant(p, 'M', 'အနက်'), l = variant(p, 'L', 'အဖြူ');
      await c.read(productServiceProvider)
          .create(p, variants: [m, l], initialStock: [into(p, 3, variantId: m.id), into(p, 2, variantId: l.id)]);
      await openEdit(tester, c, p);
      await pickExpiryWarn(tester, warn30Label);
      await typeBatchNo(tester, 'F1');
      await pickAddProductExpiry(tester, 28);
      final n0 = kinds(c).length;
      await saveForm(tester);
      expect((onForm(), kinds(c).sublist(n0).join(',')), (false, 'UnitKind.upsertProduct'));
      final b = db(c).batches.singleWhere((x) => x.productId == p.id);
      expect((stockWhere(c, (x) => x.variantId == m.id), stockWhere(c, (x) => x.variantId == l.id)), (Qty.units(3), Qty.units(2)),
          reason: 'size stock unchanged');
      expect((stockWhere(c, (x) => x.batchId == b.id), productStock(c, p.id)), (Qty.units(5), Qty.units(5)));
      expect(stockWhere(c, (x) => x.productId == p.id && x.batchId == null), 0);
      expect(stockWhere(c, (x) => x.batchId == b.id && x.variantId == m.id), Qty.units(3), reason: 'per size group');
    });

    // Two phones: B (offline, still sees the product as plain) received 5 "Batch မပါ" after A switched it to tracked.
    // After sync the tracked product has 5 outside batches again; the edit form is the way back (note for 5, ONE unit).
    testWidgets('tracked product with OPEN (10) that got 5 loose from another phone → edit form asks for a batch for the 5 '
        '(also for a plain price edit); "OPEN" refused, "LATE5" → 0 loose, OPEN 10, LATE5 5', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R6 med synced loose', expiryAlertDays: 30);
      final open = batch(p, 'OPEN', DateTime.utc(2030, 1, 1));
      await c.read(productServiceProvider).create(p, batches: [open], initialStock: [into(p, 10, batchId: open.id)]);
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(5)); // as pulled from phone B
      expect(stockWhere(c, (m) => m.productId == p.id && m.batchId == null), Qty.units(5));
      await openEdit(tester, c, p);
      expect(find.textContaining('လက်ရှိ Batch မရှိတဲ့ stock 5 ခု ကို'), findsOneWidget);
      await tester.enterText(field('price'), '700');
      final n0 = kinds(c).length;
      await saveForm(tester);
      expect((onForm(), kinds(c).length), (true, n0), reason: 'blocked until the 5 get a batch (by design, 667a0e2)');
      await typeBatchNo(tester, 'OPEN');
      await pickAddProductExpiry(tester, 28);
      await saveForm(tester);
      expect((onForm(), find.text('ဒီ Batch ရှိပြီးသားပါ။').evaluate().length), (true, 1));
      await typeBatchNo(tester, 'LATE5');
      await saveForm(tester);
      expect(onForm(), isFalse);
      final late = db(c).batches.singleWhere((x) => x.productId == p.id && x.batchNo == 'LATE5');
      expect((stockWhere(c, (m) => m.batchId == open.id), stockWhere(c, (m) => m.batchId == late.id),
              stockWhere(c, (m) => m.productId == p.id && m.batchId == null), db(c).products.firstWhere((x) => x.id == p.id).price),
          (Qty.units(10), Qty.units(5), 0, 700));
    });

    testWidgets('no opening batch asked: untracked product sold below zero (−1 loose), and "သက်တမ်း မမှတ်ပါ" picked again',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R6 med negative');
      await c.read(productServiceProvider).create(p);
      await sell(c, [line(p)]);
      await openEdit(tester, c, p);
      await pickExpiryWarn(tester, warn30Label);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsNothing, reason: 'loose stock −1: nothing to move');
      final n0 = kinds(c).length;
      await saveForm(tester);
      expect((onForm(), kinds(c).sublist(n0).join(',')), (false, 'UnitKind.upsertProduct'));
      expect(db(c).batches.where((x) => x.productId == p.id), isEmpty);

      final q = newProduct(c, 'QA R6 med back to none');
      await c.read(productServiceProvider).create(q, initialStock: [into(q, 10)]);
      await openEdit(tester, c, q);
      await pickExpiryWarn(tester, warn30Label);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsOneWidget);
      await pickExpiryWarn(tester, noExpiryLabel);
      expect(find.byKey(const ValueKey('openingBatchNote')), findsNothing);
      await saveForm(tester);
      expect(onForm(), isFalse, reason: 'plain again: saves without a batch');
      expect(db(c).products.firstWhere((x) => x.id == q.id).expiryAlertDays, isNull);
      expect(db(c).batches.where((x) => x.productId == q.id), isEmpty);
    });
  });

  // ================================================================ BUG-23 / TC-PROD-NEW-28
  group('TC-PROD-NEW-28 (BUG-23) void after a trade-in: edge cases', () {
    Future<(Product, ProductSerial, Product)> phoneAndCase(ProviderContainer c, String imei) async {
      final p = newProduct(c, 'QA R6 phone $imei');
      final old = serial(p, imei);
      await c.read(productServiceProvider).create(p, serials: [old], initialStock: [into(p, 1)]);
      final cover = newProduct(c, 'QA R6 cover $imei');
      await c.read(productServiceProvider).create(cover, initialStock: [into(cover, 5)]);
      return (p, old, cover);
    }

    int inStockRows(ProviderContainer c, String imei) =>
        db(c).serials.where((s) => s.serial == imei && s.status == SerialStatus.inStock && s.deletedAt == null).length;

    testWidgets('sale 1 = traded-in phone + 2 covers → void: covers back (+2), phone line skipped (old row sold, 1 in-stock row, '
        'phone stock 1); un-void: covers −2, phone stays 1; void again: same as the first void; POS offers the IMEI once',
        (tester) async {
      final c = await boot(tester, 'phone');
      const imei = '357000000000001';
      final (p, old, cover) = await phoneAndCase(c, imei);
      final sale1 = await sell(c, [line(p, serialId: old.id), line(cover, units: 2)]);
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [imei]);
      final fresh = db(c).serials.singleWhere((s) => s.serial == imei && s.id != old.id);

      final n0 = kinds(c).length;
      await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
      expect(kinds(c).sublist(n0), [UnitKind.voidSale]);
      String state() => 'phone ${Qty.format(productStock(c, p.id))}, cover ${Qty.format(productStock(c, cover.id))}, '
          'in-stock rows ${inStockRows(c, imei)}, old ${db(c).serials.singleWhere((s) => s.id == old.id).status.name}, '
          'new ${db(c).serials.singleWhere((s) => s.id == fresh.id).status.name}';
      expect(state(), 'phone 1, cover 5, in-stock rows 1, old sold, new inStock', reason: 'void');
      expect(db(c).serials.singleWhere((s) => s.id == old.id).saleLineId, sale1.lines.first.id, reason: 'history kept');
      expect(db(c).stock.where((m) => m.saleId == sale1.id && m.productId == p.id && m.type == StockMovementType.voidReturn),
          isEmpty, reason: 'no voidReturn for the traded-in line');

      await c.read(voidSaleServiceProvider).setVoided(sale1.id, false);
      expect(state(), 'phone 1, cover 3, in-stock rows 1, old sold, new inStock', reason: 'un-void');

      await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
      expect(state(), 'phone 1, cover 5, in-stock rows 1, old sold, new inStock', reason: 'void again');

      await tapInPos(tester, c, p.name);
      expect(inSheet(find.text(imei)), findsOneWidget, reason: 'POS offers the IMEI once');
    });

    testWidgets('normal IMEI sale (no trade-in): void → row in stock, +1; un-void → row sold with sale 1\'s line, stock 0',
        (tester) async {
      final c = await boot(tester, 'phone');
      const imei = '357000000000002';
      final (p, old, _) = await phoneAndCase(c, imei);
      final sale1 = await sell(c, [line(p, serialId: old.id)]);
      await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
      expect((db(c).serials.singleWhere((s) => s.id == old.id).status, productStock(c, p.id)), (SerialStatus.inStock, Qty.units(1)));
      await c.read(voidSaleServiceProvider).setVoided(sale1.id, false);
      final row = db(c).serials.singleWhere((s) => s.id == old.id);
      expect((row.status, row.saleLineId, productStock(c, p.id)), (SerialStatus.sold, sale1.lines.single.id, 0));
    });

    // New (round 6): the traded-in phone was sold AGAIN (sale 2, the phone is with customer 2) before sale 1 is voided.
    // Decision 3 + BUG-23 fix: the phone came back once (trade-in) — voiding sale 1 must not put it in stock a second time.
    testWidgets('trade-in row sold again (sale 2), THEN sale 1 is voided → the IMEI must not come back into stock '
        '(the phone is with customer 2)', (tester) async {
      final c = await boot(tester, 'phone');
      const imei = '357000000000003';
      final (p, old, _) = await phoneAndCase(c, imei);
      final sale1 = await sell(c, [line(p, serialId: old.id)]);
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [imei]);
      final fresh = db(c).serials.singleWhere((s) => s.serial == imei && s.id != old.id);
      await sell(c, [line(p, serialId: fresh.id)]);
      expect((inStockRows(c, imei), productStock(c, p.id)), (0, 0), reason: 'before the void: phone with customer 2');

      await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
      await tapInPos(tester, c, p.name);
      final offered = inSheet(find.text(imei)).evaluate().length;
      final oldStatus = db(c).serials.singleWhere((s) => s.id == old.id).status.name;
      expect((inStockRows(c, imei), productStock(c, p.id)), (0, 0),
          reason: 'the phone came back only once (trade-in) and was sold again. Actual: old row $oldStatus, '
              '${inStockRows(c, imei)} in-stock rows, stock ${Qty.format(productStock(c, p.id))}, POS offers it $offered×');
    });
  });
}
