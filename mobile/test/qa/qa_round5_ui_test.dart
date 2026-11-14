// QA round 5 — re-test of BUG-19 / BUG-20 (2b74d73) and the owner's decisions (f5b6e3b: expiry opt-in, batch + expiry
// for tracked opening stock, trade-in IMEIs), plus the paths next to them that no test covered yet.
// Widget tests on the app's screens with the fake repositories (no network).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
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
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import 'qa_form_helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, String template, {double height = 1600}) async {
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
  bool selected(WidgetTester tester, String key) =>
      tester
          .widget<Semantics>(find
              .ancestor(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true))
              .first)
          .properties
          .selected ==
      true;

  final t0 = DateTime.utc(2026, 10, 1);

  Product newProduct(ProviderContainer c, String name, {int? expiryAlertDays}) => Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0, expiryAlertDays: expiryAlertDays,
      );
  ProductSerial serial(Product p, String imei, {SerialStatus status = SerialStatus.inStock}) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: status, createdAt: t0, updatedAt: t0);
  ProductBatch batch(Product p, String no, DateTime? exp) => ProductBatch(
      id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: no, qtyMilli: 0, expiryDate: exp, createdAt: t0, updatedAt: t0);
  StockMovement into(Product p, int units, {String? batchId}) => restockMovement(
      tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: batchId, note: 'initial');

  Future<void> openProducts(WidgetTester tester, ProviderContainer c, String search) async {
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, search);
    await tester.pumpAndSettle();
  }

  Future<void> openRestock(WidgetTester tester, ProviderContainer c, Product p) async {
    await openProducts(tester, c, p.name);
    await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester, ProviderContainer c, Product p) async {
    await openProducts(tester, c, p.name);
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget);
  }

  Future<void> keys(WidgetTester tester, List<String> ks) async {
    for (final k in ks) {
      await tester.tap(inSheet(find.text(k)).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> saveSheet(WidgetTester tester) async {
    await tester.tap(inSheet(find.text('သိမ်းမယ်')));
    await tester.pumpAndSettle();
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
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

  // ================================================================ BUG-19 / TC-PROD-NEW-22
  group('TC-PROD-NEW-22 (BUG-19) Add Product: a typed IMEI is never lost, a refused one blocks the save', () {
    testWidgets('one IMEI added with Enter + a second one only typed → both saved in stock, stock 2, ONE upsertProduct',
        (tester) async {
      final c = await boot(tester, 'phone');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R5 two IMEIs');
      await tester.enterText(field('price'), '450000');
      await tester.enterText(field('imei'), '352000000000001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('352000000000001'), findsOneWidget, reason: 'the Enter-ed IMEI is in the list');
      await tester.enterText(field('imei'), '352000000000002'); // typed / scanned without Enter
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveForm(tester);
      final p = db(c).products.where((x) => x.name == 'QA R5 two IMEIs').singleOrNull;
      expect(p, isNotNull);
      final rows = db(c).serials.where((s) => s.productId == p!.id).toList();
      expect(rows.map((s) => '${s.serial}/${s.status.name}').toList()..sort(),
          ['352000000000001/inStock', '352000000000002/inStock']);
      expect(productStock(c, p!.id), Qty.units(2));
      expect(kinds(c).sublist(n), [UnitKind.upsertProduct], reason: 'product + IMEIs + stock in ONE unit');
    });

    testWidgets('typed IMEI equal to one already in the list → save blocked with "ဒီ IMEI ထည့်ပြီးသားပါ။", nothing written; '
        'clearing it then saves with the one IMEI', (tester) async {
      final c = await boot(tester, 'phone');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R5 dup typed');
      await tester.enterText(field('price'), '450000');
      await tester.enterText(field('imei'), '352000000000011');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(field('imei'), '352000000000011');
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveForm(tester);
      expect(db(c).products.where((x) => x.name == 'QA R5 dup typed'), isEmpty, reason: 'refused typed IMEI blocks the save');
      expect(kinds(c).length, n, reason: 'nothing written');
      expect(find.text('ဒီ IMEI ထည့်ပြီးသားပါ။'), findsOneWidget, reason: 'the reason is shown');
      await tester.enterText(field('imei'), '');
      await tester.pumpAndSettle();
      await saveForm(tester);
      final p = db(c).products.where((x) => x.name == 'QA R5 dup typed').singleOrNull;
      expect(p, isNotNull);
      expect(db(c).serials.where((s) => s.productId == p!.id).map((s) => s.serial), ['352000000000011']);
      expect(productStock(c, p!.id), Qty.units(1));
    });
  });

  // ================================================================ BUG-20 / TC-PROD-NEW-23
  group('TC-PROD-NEW-23 (BUG-20) a no-expiry product WITH old batches restocks and sells as a plain product', () {
    testWidgets('pharmacy: soap (no expiryAlertDays) with batch S1 (3 left) + expired S0 → "Stock ဖြည့်မယ်" shows only '
        '"Batch မပါ" (selected), no old batch, no "+ Batch အသစ်"; +5 outside batches; POS: no sheet, no confirm, line without '
        'batch; stock = all movements', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 1000);
      final p = newProduct(c, 'QA R5 soap with batches');
      final s1 = batch(p, 'S1', DateTime.utc(2030, 1, 1));
      final s0 = batch(p, 'S0', DateTime.utc(2021, 1, 1));
      await c.read(productServiceProvider)
          .create(p, batches: [s1, s0], initialStock: [into(p, 3, batchId: s1.id), into(p, 1, batchId: s0.id)]);

      await openRestock(tester, c, p);
      expect(find.byKey(ValueKey('restockBatch-${s1.id}')), findsNothing, reason: 'old batches are not offered');
      expect(find.byKey(ValueKey('restockBatch-${s0.id}')), findsNothing);
      expect(find.byKey(const ValueKey('restockBatch-new')), findsNothing, reason: 'no new batch for a no-expiry product');
      expect(selected(tester, 'restockBatch-none'), isTrue, reason: '"Batch မပါ" is the (only) choice');
      await keys(tester, ['5']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.restock]);
      expect(db(c).stock.last.batchId, isNull);
      expect(db(c).batches.where((b) => b.productId == p.id), hasLength(2), reason: 'no batch created');
      expect(productStock(c, p.id), Qty.units(9));

      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsNothing, reason: 'no batch sheet');
      expect(find.textContaining('သက်တမ်းကုန်နေပါပြီ'), findsNothing, reason: 'no expired confirm (S0 is expired)');
      expect(c.read(cartProvider).lines.single.batchId, isNull);
      await tester.tap(find.text('ငွေရှင်းမယ်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
      await tester.pumpAndSettle();
      expect(db(c).sales.expand((s) => s.lines).where((l) => l.productId == p.id).single.batchId, isNull);
      expect(productStock(c, p.id), Qty.units(8), reason: 'stock = all movements');
      expect(stockWhere(c, (m) => m.batchId == s1.id), Qty.units(3), reason: 'S1 untouched by the plain sale');
    });

    testWidgets('pharmacy: UNTRACKED no-expiry soap sold 1 → "Stock ဖြည့်မယ်" ("Batch မပါ") 20 → shows 20, not 19 '
        '(TC-PROD-06 rule), ONE stockAdjust unit, no batch', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 1000);
      final p = newProduct(c, 'QA R5 untracked soap');
      await c.read(productServiceProvider).create(p);
      await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
        (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400),
      ], method: PaymentMethod.cash));
      await openRestock(tester, c, p);
      expect(selected(tester, 'restockBatch-none'), isTrue);
      await keys(tester, ['2', '0']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.stockAdjust], reason: 'first count of an untracked product');
      expect(productStock(c, p.id), Qty.units(20));
      expect(db(c).batches.where((b) => b.productId == p.id), isEmpty);
    });
  });

  // ================================================================ new: TC-PROD-NEW-24
  // Item 5: "batches are required only for products with expiryAlertDays set"; decision 2: "an expiry-tracked product
  // cannot be saved with opening stock unless a batch number (and expiry) is entered". Decision 1 makes "သက်တမ်း မမှတ်ပါ"
  // the default, so a medicine added with stock and the default is plain; the owner then corrects it in the edit form.
  group('TC-PROD-NEW-24 edit form: switching a product WITH stock to expiry tracking', () {
    testWidgets('plain medicine with 10 in stock (no batch) → edit → "ရက် ၃၀ အလို" → save: refused / asks for a batch, '
        'or the 10 go into a batch — a tracked product never keeps stock outside batches unnoticed', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 1000);
      final p = newProduct(c, 'QA R5 med forgot expiry');
      await c.read(productServiceProvider).create(p, initialStock: [into(p, 10)]);
      await openEdit(tester, c, p);
      await pickExpiryWarn(tester, warn30Label);
      await saveForm(tester);
      final saved = db(c).products.firstWhere((x) => x.id == p.id);
      final outside = stockWhere(c, (m) => m.productId == p.id && m.batchId == null);
      final stillOnForm = find.text('ပစ္စည်း ပြင်မယ်').evaluate().isNotEmpty;

      // Consequence (recorded): the next delivery must go into a batch; POS then sells from it.
      var record = '';
      if (saved.expiryAlertDays != null && outside > 0) {
        final b1 = ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'B1', qtyMilli: Qty.units(5),
            expiryDate: DateTime.utc(2030, 6, 30), createdAt: t0, updatedAt: t0);
        await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(5), newBatch: b1);
        await tapInPos(tester, c, p.name);
        final asked = find.text('ဘယ် Batch လဲ?').evaluate().isNotEmpty;
        final first = c.read(cartProvider).lines.firstOrNull?.batchId == b1.id ? 'B1' : 'other';
        c.read(cartProvider.notifier).clear();
        // 5 more sales the way POS just picked them (from B1) → B1 empty, 10 still outside batches
        for (var i = 0; i < 5; i++) {
          await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
            (productId: p.id, variantId: null, batchId: b1.id, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400),
          ], method: PaymentMethod.cash));
        }
        await tapInPos(tester, c, p.name);
        final offered = inSheet(find.textContaining('ကျန်')).evaluate().map((e) => (e.widget as Text).data).toList();
        record = 'saved with expiryAlertDays ${saved.expiryAlertDays}, ${Qty.format(outside)} outside any batch, form '
            '${stillOnForm ? 'still open' : 'closed'}, no message; after receiving B1 × 5, POS '
            '${asked ? 'asks' : 'auto-picks'} → cart batch = $first; after 5 sales from B1 (product stock '
            '${Qty.format(productStock(c, p.id))}) POS offers $offered';
      }
      expect(saved.expiryAlertDays == null || outside == 0, isTrue,
          reason: 'a tracked product must not keep stock outside batches unnoticed. Actual: $record');
    });
  });

  // ================================================================ new: TC-PROD-NEW-25
  // Owner decision 3 (trade-in): "an IMEI whose last status is 'sold' can be received again (new inStock row, history kept);
  // an IMEI that is 'inStock' is still refused".
  group('TC-PROD-NEW-25 trade-in: re-received IMEI is sold again', () {
    testWidgets('sold X re-received → POS offers X once and sells the NEW row; the old row keeps its sale line', (tester) async {
      final c = await boot(tester, 'phone', height: 1000);
      final p = newProduct(c, 'QA R5 trade-in phone');
      final old = serial(p, '353000000000001');
      await c.read(productServiceProvider).create(p, serials: [old], initialStock: [into(p, 1)]);
      final sale1 = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
        (productId: p.id, variantId: null, batchId: null, serialId: old.id, name: p.name, qtyMilli: 1000, price: 600, cost: 400),
      ], method: PaymentMethod.cash));
      final line1 = sale1.lines.single.id;
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: ['353000000000001']);
      final fresh = db(c).serials.singleWhere((s) => s.serial == '353000000000001' && s.id != old.id);
      expect(fresh.status, SerialStatus.inStock);

      await tapInPos(tester, c, p.name);
      expect(inSheet(find.text('353000000000001')), findsOneWidget, reason: 'offered once (only the in-stock row)');
      await tester.tap(inSheet(find.text('353000000000001')));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.serialId, fresh.id);
      await tester.tap(find.text('ငွေရှင်းမယ်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
      await tester.pumpAndSettle();
      final rows = {for (final s in db(c).serials.where((s) => s.serial == '353000000000001')) s.id: s};
      expect(rows[old.id]!.status, SerialStatus.sold);
      expect(rows[old.id]!.saleLineId, line1, reason: 'history: the first sale line stays on the old row');
      expect(rows[fresh.id]!.status, SerialStatus.sold);
      expect(rows[fresh.id]!.saleLineId, isNot(line1));
      expect(productStock(c, p.id), 0);
    });
  });

  // ================================================================ new: TC-PROD-NEW-26 (BUG-23)
  group('TC-PROD-NEW-26 trade-in, then the ORIGINAL sale is voided', () {
    testWidgets('sold X re-received (in stock again), then the ORIGINAL sale is voided → X must not be in stock twice '
        'unnoticed (refused, warned, or one row)', (tester) async {
      final c = await boot(tester, 'phone', height: 1000);
      final p = newProduct(c, 'QA R5 trade-in void');
      final old = serial(p, '353000000000002');
      await c.read(productServiceProvider).create(p, serials: [old], initialStock: [into(p, 1)]);
      final sale1 = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
        (productId: p.id, variantId: null, batchId: null, serialId: old.id, name: p.name, qtyMilli: 1000, price: 600, cost: 400),
      ], method: PaymentMethod.cash));
      await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: ['353000000000002']);
      Object? error;
      try {
        await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
      } catch (e) {
        error = e;
      }
      final inStock = db(c).serials.where((s) => s.serial == '353000000000002' && s.status == SerialStatus.inStock).length;
      await tapInPos(tester, c, p.name);
      final offered = inSheet(find.text('353000000000002')).evaluate().length;
      expect(inStock, lessThanOrEqualTo(1),
          reason: 'owner decision 3: an in-stock IMEI is never duplicated. Actual: void ${error == null ? 'accepted' : 'refused ($error)'}, '
              '$inStock in-stock rows for the IMEI, stock ${Qty.format(productStock(c, p.id))}, POS offers it $offered×');
    });
  });
}
