// QA round 4 — re-test of BUG-15 / 16 / 17 / 18 (app side) and the owner's pharmacy decision (item 5, f3a7e0f):
// "batches are required only for products with expiryAlertDays set; products without it (soap etc.) sell and restock
// like plain products even when the Batch feature is on".
// Widget tests on the app's screens with the fake repositories (no network).
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
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart' show SaleLineDraft;
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

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
  ProductVariant variant(Product p, String size, String color) => ProductVariant(
      id: newId(), tenantId: p.tenantId, productId: p.id, size: size, color: color, createdAt: t0, updatedAt: t0);
  StockMovement into(Product p, int units, {String? batchId, String? variantId}) => restockMovement(
      tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: batchId, variantId: variantId, note: 'initial');
  SaleLineDraft line(Product p, {String? batchId, String? variantId}) =>
      (productId: p.id, variantId: variantId, batchId: batchId, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400);

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

  // ================================================================ BUG-15 / TC-PROD-NEW-11
  group('TC-PROD-NEW-11 (BUG-15) first count of an untracked batch / size product = what was counted', () {
    testWidgets('pharmacy, expiry-tracked (30 d): sold 1 → "+ Batch အသစ်" FIRST × 20 → 20 in FIRST, 0 outside batches, '
        'ONE stockAdjust unit, tracked afterwards; the next delivery is a normal restock', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R4 untracked med', expiryAlertDays: 30);
      await c.read(productServiceProvider).create(p);
      await sell(c, [line(p)]);
      expect(productStock(c, p.id), -1000);

      await openRestock(tester, c, p);
      expect(find.byKey(const ValueKey('restockBatch-none')), findsNothing, reason: 'expiry-tracked: a batch is required');
      expect(selected(tester, 'restockBatch-new'), isTrue, reason: 'no batch yet: "+ Batch အသစ်" is the default');
      await tester.enterText(field('restockBatchNo'), 'FIRST');
      await keys(tester, ['2', '0']);
      final n = kinds(c).length;
      await saveSheet(tester);

      expect(kinds(c).sublist(n), [UnitKind.stockAdjust], reason: 'first count = ONE stockAdjust unit');
      expect(productStock(c, p.id), Qty.units(20), reason: 'TC-PROD-06 rule: shows 20, not 19');
      final first = db(c).batches.singleWhere((b) => b.productId == p.id && b.batchNo == 'FIRST');
      expect(stockWhere(c, (m) => m.batchId == first.id), Qty.units(20), reason: 'batch stock = what was counted');
      expect(stockWhere(c, (m) => m.productId == p.id && m.batchId == null), 0, reason: 'the old sale is zeroed outside batches');
      final adj = db(c).stock.where((m) => m.productId == p.id && m.type == StockMovementType.adjustment).toList();
      expect(adj.map((m) => (m.qtyMilli, m.batchId, m.note)), [(1000, null, 'opening count')]);
      expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).isUntracked, isFalse);

      await openRestock(tester, c, p);
      expect(selected(tester, 'restockBatch-${first.id}'), isTrue);
      await keys(tester, ['5']);
      final n2 = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n2), [UnitKind.restock], reason: 'tracked now: a normal delivery');
      expect(productStock(c, p.id), Qty.units(25));
    });

    testWidgets('pharmacy: untracked product with an EMPTY batch B0, sold 1 from B0 (B0 −1) → count 20 into B0 → B0 = 20 = product',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R4 B0 med', expiryAlertDays: 30);
      final b0 = batch(p, 'B0', DateTime.utc(2030, 1, 31));
      await c.read(productServiceProvider).create(p, batches: [b0]);
      await sell(c, [line(p, batchId: b0.id)]);
      await openRestock(tester, c, p);
      expect(selected(tester, 'restockBatch-${b0.id}'), isTrue);
      await keys(tester, ['2', '0']);
      await saveSheet(tester);
      expect(stockWhere(c, (m) => m.batchId == b0.id), Qty.units(20));
      expect(productStock(c, p.id), Qty.units(20));
    });

    testWidgets('fashion: M·အဖြူ and L·အနက်, untracked, 1 sold from M → count 20 into L → M 0, L 20, product 20',
        (tester) async {
      final c = await boot(tester, 'fashion');
      final p = newProduct(c, 'QA R4 untracked shirt');
      final m = variant(p, 'M', 'အဖြူ'), l = variant(p, 'L', 'အနက်');
      await c.read(productServiceProvider).create(p, variants: [m, l]);
      await sell(c, [line(p, variantId: m.id)]);
      await openRestock(tester, c, p);
      await tester.tap(find.byKey(ValueKey('restockVariant-${l.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['2', '0']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.stockAdjust]);
      expect((stockWhere(c, (x) => x.variantId == m.id), stockWhere(c, (x) => x.variantId == l.id), productStock(c, p.id)),
          (0, Qty.units(20), Qty.units(20)), reason: 'variant stock adds up to product stock');
    });
  });

  // ================================================================ BUG-16 / TC-PROD-NEW-12
  group('TC-PROD-NEW-12 (BUG-16) "+ Batch အသစ်" refuses an existing batch number', () {
    testWidgets('"B1" and " B1 " refused with the message, nothing written, sheet stays; "B2" then saves', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R4 dup batch', expiryAlertDays: 30);
      final b1 = batch(p, 'B1', DateTime.utc(2030, 6, 30));
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [into(p, 2, batchId: b1.id)]);
      final n = kinds(c).length;
      await openRestock(tester, c, p);
      await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
      await tester.pumpAndSettle();
      await keys(tester, ['5']);
      for (final no in ['B1', ' B1 ']) {
        await tester.enterText(field('restockBatchNo'), no);
        await tester.pump(); // a frame: the save button follows the typed text (a real user always gets one)
        await saveSheet(tester);
        expect(inSheet(find.text('ဒီ Batch ရှိပြီးသားပါ။')), findsOneWidget, reason: '"$no" must be refused');
        expect(kinds(c).length, n, reason: 'nothing written');
      }
      await tester.enterText(field('restockBatchNo'), 'B2');
      await tester.pump();
      await saveSheet(tester);
      expect(db(c).batches.where((b) => b.productId == p.id).map((b) => b.batchNo).toList()..sort(), ['B1', 'B2']);
      expect(productStock(c, p.id), Qty.units(7));
    });
  });

  // ================================================================ BUG-17 / TC-PROD-NEW-13
  group('TC-PROD-NEW-13 (BUG-17) edit form: typed but not added = added on save, or save blocked', () {
    testWidgets('phone: typed IMEI → saved in ONE upsertProduct, in stock, stock +1', (tester) async {
      final c = await boot(tester, 'phone');
      final p = newProduct(c, 'QA R4 typed IMEI');
      await c.read(productServiceProvider).create(p, serials: [serial(p, '810000000000001')], initialStock: [into(p, 1)]);
      await openEdit(tester, c, p);
      await tester.enterText(field('newImei'), '810000000000002');
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveForm(tester);
      expect(find.text('ပစ္စည်း ပြင်မယ်'), findsNothing, reason: 'saved and closed');
      expect(kinds(c).sublist(n), [UnitKind.upsertProduct]);
      expect(db(c).serials.singleWhere((s) => s.serial == '810000000000002').status, SerialStatus.inStock);
      expect(productStock(c, p.id), Qty.units(2));
    });

    testWidgets('pharmacy: typed batch no. → batch created; fashion: size typed without colour → save blocked, nothing written',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA R4 typed batch', expiryAlertDays: 30);
      await c.read(productServiceProvider).create(p, batches: [batch(p, 'OLD', DateTime.utc(2030, 1, 1))]);
      await openEdit(tester, c, p);
      await tester.enterText(field('newBatchNo'), 'TYPED');
      await tester.pumpAndSettle();
      await saveForm(tester);
      expect(db(c).batches.where((b) => b.productId == p.id).map((b) => b.batchNo).toSet(), {'OLD', 'TYPED'});
    });

    testWidgets('fashion: size typed without colour → save blocked with "Size နဲ့ အရောင် ထည့်ပါ။", nothing written',
        (tester) async {
      final c = await boot(tester, 'fashion');
      final p = newProduct(c, 'QA R4 typed size');
      final m = variant(p, 'M', 'အနက်');
      await c.read(productServiceProvider).create(p, variants: [m], initialStock: [into(p, 1, variantId: m.id)]);
      await openEdit(tester, c, p);
      await tester.enterText(field('newVariantSize'), 'XL');
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveForm(tester);
      expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget, reason: 'still on the form');
      expect(find.text('Size နဲ့ အရောင် ထည့်ပါ။'), findsOneWidget);
      expect(kinds(c).length, n);
      expect(db(c).variants.where((v) => v.productId == p.id), hasLength(1));
    });
  });

  // ================================================================ TC-PROD-NEW-15 Add Product typed IMEI
  group('TC-PROD-NEW-15 Add Product (new product): an IMEI typed but not "+"-ed', () {
    testWidgets('phone: type an IMEI in Add Product and tap သိမ်းမယ် without Enter / "+" → saved, or the form warns',
        (tester) async {
      final c = await boot(tester, 'phone');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('productName'), 'QA R4 new phone');
      await tester.enterText(field('price'), '450000');
      await tester.enterText(field('imei'), '351999999999991');
      await tester.pumpAndSettle();
      await saveForm(tester);
      final p = db(c).products.where((x) => x.name == 'QA R4 new phone').firstOrNull;
      final saved = p != null && db(c).serials.any((s) => s.productId == p.id && s.serial == '351999999999991');
      final warned = p == null && find.byKey(const ValueKey('imei')).evaluate().isNotEmpty;
      expect(saved || warned, isTrue,
          reason: 'same rule as BUG-17 (edit form) and the restock sheet: a typed IMEI is never silently dropped '
              '(product saved: ${p != null}, IMEIs: ${p == null ? '-' : db(c).serials.where((s) => s.productId == p.id).length}, '
              'stock: ${p == null ? '-' : productStock(c, p.id)})');
    });
  });

  // ================================================================ BUG-18 app / TC-PROD-NEW-14
  group('TC-PROD-NEW-14 (BUG-18 app) an IMEI the phone knows on ANY product, also SOLD, is refused', () {
    testWidgets('"Stock ဖြည့်မယ်" and Add Product refuse an IMEI sold on another product; nothing written', (tester) async {
      final c = await boot(tester, 'phone');
      final a = newProduct(c, 'QA R4 phone A'), b = newProduct(c, 'QA R4 phone B');
      await c.read(productServiceProvider).create(a, serials: [serial(a, '820000000000001', status: SerialStatus.sold)]);
      await c.read(productServiceProvider).create(b, serials: [serial(b, '820000000000002')], initialStock: [into(b, 1)]);
      final n = kinds(c).length;
      await openRestock(tester, c, b);
      await tester.enterText(field('imei'), '820000000000001');
      await tester.pump();
      await tester.tap(inSheet(find.text('+ ထည့်')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('ဒီ IMEI ရှိပြီးသားပါ။')), findsOneWidget);
      await saveSheet(tester); // the refused IMEI is still typed
      expect(kinds(c).length, n, reason: 'a refused IMEI is not saved by "သိမ်းမယ်"');
      expect(db(c).serials.where((s) => s.serial == '820000000000001'), hasLength(1));
    });
  });

  // ================================================================ item 5 — owner's pharmacy decision
  group('item 5: products without expiryAlertDays sell and restock like plain products (Batch feature on)', () {
    testWidgets('TC-PROD-NEW-16 edit form round trip: a no-expiry product opens with "သက်တမ်း မမှတ်ပါ" + the help text, '
        'saving keeps it null; a tracked one keeps its days', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final soap = newProduct(c, 'QA R4 soap');
      final med = newProduct(c, 'QA R4 med 60', expiryAlertDays: 60);
      await c.read(productServiceProvider).create(soap, initialStock: [into(soap, 3)]);
      await c.read(productServiceProvider).create(med);
      await openEdit(tester, c, soap);
      expect(find.descendant(of: find.byKey(const ValueKey('expiryWarn')), matching: find.text('သက်တမ်း မမှတ်ပါ')), findsOneWidget);
      expect(find.byKey(const ValueKey('expiryHelp')), findsOneWidget);
      await saveForm(tester);
      expect(db(c).products.firstWhere((x) => x.id == soap.id).expiryAlertDays, isNull);
      await openEdit(tester, c, med);
      expect(find.descendant(of: find.byKey(const ValueKey('expiryWarn')), matching: find.text('ရက် ၆၀ အလို')), findsOneWidget);
      await saveForm(tester);
      expect(db(c).products.firstWhere((x) => x.id == med.id).expiryAlertDays, 60);
    });

    testWidgets('TC-PROD-NEW-17 grocery with "သက်တမ်းကုန်ရက် / Batch" turned on: a product without batches restocks '
        '"Batch မပါ" by default (plain restock) and sells without a batch sheet', (tester) async {
      final c = await boot(tester, 'grocery');
      c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.expiryBatch, true);
      await tester.pumpAndSettle();
      final p = newProduct(c, 'QA R4 grocery soap');
      await c.read(productServiceProvider).create(p, initialStock: [into(p, 4)]);
      await openRestock(tester, c, p);
      expect(selected(tester, 'restockBatch-none'), isTrue);
      await keys(tester, ['3']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.restock]);
      expect(db(c).stock.last.batchId, isNull);
      expect(db(c).batches.where((b) => b.productId == p.id), isEmpty);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsNothing);
      expect(c.read(cartProvider).lines.single.batchId, isNull);
    });

    testWidgets('TC-PROD-NEW-18 product switched to "သက်တမ်း မမှတ်ပါ" that still has an old EMPTY batch, goods since '
        'received "Batch မပါ" → POS sells it like a plain product', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 844);
      final p = newProduct(c, 'QA R4 switched soap'); // expiryAlertDays null = "သက်တမ်း မမှတ်ပါ"
      final s1 = batch(p, 'S1', DateTime.utc(2030, 1, 1));
      await c.read(productServiceProvider).create(p, batches: [s1], initialStock: [into(p, 10)]); // 10 without batch, S1 = 0
      await tapInPos(tester, c, p.name);
      final asked = find.text('ဘယ် Batch လဲ?').evaluate().isNotEmpty;
      var record = '';
      if (asked) {
        final offered = inSheet(find.textContaining('ကျန်')).evaluate().map((e) => (e.widget as Text).data).toList();
        await tester.tap(inSheet(find.textContaining('S1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ငွေရှင်းမယ်'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
        await tester.pumpAndSettle();
        record = 'sheet offered $offered; after selling it S1 = ${Qty.format(stockWhere(c, (m) => m.batchId == s1.id))}';
      }
      expect(asked, isFalse,
          reason: 'owner: a product without expiryAlertDays sells like a plain product. Actual: $record');
      expect(c.read(cartProvider).lines.single.batchId, isNull);
    });

    testWidgets('TC-PROD-NEW-18 same, old batch EXPIRED and empty → no batch sheet and no "expired" confirm for soap',
        (tester) async {
      final c = await boot(tester, 'pharmacy', height: 844);
      final p = newProduct(c, 'QA R4 switched soap exp');
      final s1 = batch(p, 'S1', DateTime.utc(2021, 1, 1));
      await c.read(productServiceProvider).create(p, batches: [s1], initialStock: [into(p, 10)]);
      await tapInPos(tester, c, p.name);
      final asked = find.text('ဘယ် Batch လဲ?').evaluate().isNotEmpty;
      if (asked) {
        await tester.tap(inSheet(find.textContaining('S1')));
        await tester.pumpAndSettle();
      }
      final confirm = find.textContaining('သက်တမ်းကုန်နေပါပြီ').evaluate().isNotEmpty;
      expect((asked, confirm), (false, false),
          reason: 'soap with no expiry tracking must not ask for a batch or an "expired" confirm on every sale');
    });

    testWidgets('TC-PROD-NEW-19 Add Product, expiry-tracked (default ရက် ၃၀): opening stock 10 with NO batch no. → '
        'refused or saved into a batch (a tracked product needs a batch)', (tester) async {
      final c = await boot(tester, 'pharmacy');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('expiryWarn')), matching: find.text('ရက် ၃၀ အလို')), findsOneWidget);
      await tester.enterText(field('productName'), 'QA R4 tracked no batch');
      await tester.enterText(field('price'), '1500');
      await tester.enterText(field('stockQty'), '10');
      await saveForm(tester);
      final p = db(c).products.where((x) => x.name == 'QA R4 tracked no batch').firstOrNull;
      final outside = p == null ? 0 : stockWhere(c, (m) => m.productId == p.id && m.batchId == null);
      expect(outside, 0,
          reason: 'owner: batches are required for products with expiryAlertDays. Actual: saved with '
              'expiryAlertDays ${p?.expiryAlertDays}, ${Qty.format(outside)} in stock outside any batch '
              '(no expiry known; once a batch is received POS auto-picks it for this stock too)');
    });
  });
}
