// QA round 3 — screens of the BUG-12 fix (restock + edit form follow the product's IMEIs / batches / sizes),
// expired batches at POS (79a18b3) and the cleared low-stock alert (3c288d7).
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
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/inventory/presentation/restock_sheet.dart' show ExpiredBadge;
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
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

  final t0 = DateTime.utc(2026, 10, 1);
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);

  // r4: medicine fixtures pass expiryAlertDays 30 — owner item 5: "batches are required only for products with
  // expiryAlertDays set; products without it (soap etc.) sell and restock like plain products". A medicine sold by
  // batch is an expiry-tracked product; the r3 seeds left the field null only because it did not matter then.
  Product newProduct(ProviderContainer c, String name, {int lowAlertMilli = 5000, String unit = '', int? expiryAlertDays}) =>
      Product(
        id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0, lowAlertMilli: lowAlertMilli, unit: unit,
        expiryAlertDays: expiryAlertDays,
      );
  ProductSerial serial(Product p, String imei, {SerialStatus status = SerialStatus.inStock}) => ProductSerial(
      id: newId(), tenantId: p.tenantId, productId: p.id, serial: imei, status: status, createdAt: t0, updatedAt: t0);
  ProductBatch batch(Product p, String no, DateTime? exp, {DateTime? created}) => ProductBatch(
      id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: no, qtyMilli: 0, expiryDate: exp,
      createdAt: created ?? t0, updatedAt: created ?? t0);
  ProductVariant variant(Product p, String size, String color) => ProductVariant(
      id: newId(), tenantId: p.tenantId, productId: p.id, size: size, color: color, createdAt: t0, updatedAt: t0);
  StockMovement into(Product p, int units, {String? batchId, String? variantId}) => restockMovement(
      tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: batchId, variantId: variantId, note: 'initial');

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

  Future<void> checkoutCash(WidgetTester tester) async {
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
  }

  // ================================================================ TC-PROD-NEW-6 restock an IMEI product
  group('TC-PROD-NEW-6 "Stock ဖြည့်မယ်" for an IMEI product', () {
    testWidgets('keypad + "+ ထည့်" list; duplicates (list / in stock) refused, a SOLD IMEI accepted (trade-in); '
        'typed-but-not-added counts; ONE restock unit; POS offers exactly the in-stock IMEIs', (tester) async {
      final c = await boot(tester, 'phone');
      final p = newProduct(c, 'QA Redmi R3');
      final sold = serial(p, '111111111111111', status: SerialStatus.sold);
      final have = serial(p, '222222222222222');
      await c.read(productServiceProvider).create(p, serials: [sold, have], initialStock: [into(p, 1)]);
      final before = productStock(c, p.id);

      await openRestock(tester, c, p);
      expect(find.byKey(const ValueKey('imei')), findsOneWidget, reason: 'IMEI products ask for IMEIs, not a count');
      expect(find.byKey(const ValueKey('qtySheetValue')), findsNothing, reason: 'no bare quantity');

      // 1) on-screen keypad + "+ ထည့်"
      await keys(tester, List.filled(15, '3'));
      await tester.tap(inSheet(find.text('+ ထည့်')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('333333333333333')), findsOneWidget);
      // 2) duplicates: in the list, already in stock → refused
      for (final dup in ['333333333333333', have.serial]) {
        await tester.enterText(field('imei'), dup);
        await tester.pump(); // a frame: the button follows the typed text
        await tester.tap(inSheet(find.text('+ ထည့်')));
        await tester.pumpAndSettle();
        expect(inSheet(find.text('ဒီ IMEI ရှိပြီးသားပါ။')), findsOneWidget, reason: '$dup must be refused');
      }
      // 2b) owner decision 3 (2026-11-14, trade-in): an IMEI whose last status is "sold" can be received again.
      await tester.enterText(field('imei'), sold.serial);
      await tester.pump();
      await tester.tap(inSheet(find.text('+ ထည့်')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('ဒီ IMEI ရှိပြီးသားပါ။')), findsNothing, reason: 'sold ${sold.serial} must be accepted (trade-in)');
      expect(tester.widget<EditableText>(field('imei')).controller.text, isEmpty, reason: 'taken into the list');
      // 3) typed (scanner) but "+ ထည့်" not tapped: saving takes it too
      await tester.enterText(field('imei'), '444444444444444');
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveSheet(tester);

      expect(kinds(c).sublist(n), [UnitKind.restock], reason: 'ONE restock unit');
      expect(productStock(c, p.id), before + Qty.units(3), reason: 'quantity = number of new IMEIs (333, traded-in 111, 444)');
      final rows = db(c).serials.where((s) => s.productId == p.id).toList();
      String key((String, SerialStatus) r) => '${r.$1}/${r.$2.name}';
      expect(rows.map((s) => key((s.serial, s.status))).toList()..sort(), [
        key((sold.serial, SerialStatus.inStock)),
        key((sold.serial, SerialStatus.sold)),
        key((have.serial, SerialStatus.inStock)),
        key(('333333333333333', SerialStatus.inStock)),
        key(('444444444444444', SerialStatus.inStock)),
      ]..sort(), reason: 'trade-in = a NEW inStock row; the sold row (history) is kept');
      final oldSold = rows.singleWhere((s) => s.id == sold.id);
      expect((oldSold.status, oldSold.updatedAt), (SerialStatus.sold, t0), reason: 'sold history row untouched');
      expect(rows.where((s) => s.serial == have.serial).single.updatedAt, t0, reason: 'existing IMEI rows untouched');

      // POS offers the four in-stock IMEIs (the traded-in 111 once); selling a received one marks it sold.
      await tapInPos(tester, c, p.name);
      for (final s in [have.serial, '333333333333333', '444444444444444', sold.serial]) {
        expect(inSheet(find.text(s)), findsOneWidget, reason: '$s is in stock (offered once)');
      }
      await tester.tap(inSheet(find.text('444444444444444')));
      await tester.pumpAndSettle();
      await checkoutCash(tester);
      final s4 = db(c).serials.singleWhere((s) => s.serial == '444444444444444');
      final line = db(c).sales.expand((s) => s.lines).singleWhere((l) => l.serialId == s4.id);
      expect((s4.status, s4.saleLineId), (SerialStatus.sold, line.id));
      expect(productStock(c, p.id), before + Qty.units(2));
    });

    testWidgets('dismissing the sheet writes nothing; an empty list cannot be saved', (tester) async {
      final c = await boot(tester, 'phone');
      final p = newProduct(c, 'QA Redmi R3b');
      await c.read(productServiceProvider).create(p, serials: [serial(p, '555555555555555')], initialStock: [into(p, 1)]);
      final n = kinds(c).length;
      await openRestock(tester, c, p);
      await saveSheet(tester); // nothing typed
      expect(kinds(c).length, n, reason: 'empty list: nothing saved');
      await tester.enterText(field('imei'), '666666666666666');
      await tester.tapAt(const Offset(195, 20)); // barrier
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('imei')), findsNothing, reason: 'sheet closed');
      expect(kinds(c).length, n, reason: 'dismiss: nothing saved');
      expect(db(c).serials.where((s) => s.productId == p.id), hasLength(1));
    });
  });

  // ================================================================ TC-PROD-NEW-7 restock a batch product
  group('TC-PROD-NEW-7 "Stock ဖြည့်မယ်" for a batch product (pharmacy)', () {
    testWidgets('default = newest UNEXPIRED batch (newest expired one is skipped and marked); goods go into it', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA Paracetamol R3', expiryAlertDays: 30);
      final good = batch(p, 'GOOD30', DateTime.utc(2030, 1, 31), created: t0);
      final newer = batch(p, 'NEWER31', DateTime.utc(2031, 1, 31), created: t0.add(const Duration(days: 1)));
      final expired = batch(p, 'EXP20', DateTime.utc(2020, 1, 31), created: t0.add(const Duration(days: 2)));
      await c.read(productServiceProvider).create(p,
          batches: [good, newer, expired], initialStock: [into(p, 2, batchId: good.id), into(p, 1, batchId: expired.id)]);
      await openRestock(tester, c, p);

      bool selected(String id) => tester
          .widget<Semantics>(find
              .ancestor(
                  of: find.byKey(ValueKey('restockBatch-$id')),
                  matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true))
              .first)
          .properties
          .selected == true;
      expect(selected(newer.id), isTrue, reason: 'newest unexpired batch is the default');
      expect(selected(expired.id), isFalse, reason: 'the newest batch is expired: not the default');
      expect(find.descendant(of: find.byKey(ValueKey('restockBatch-${expired.id}')), matching: find.text(ExpiredBadge.label)),
          findsOneWidget, reason: 'expired batch marked');
      await keys(tester, ['6']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.restock]);
      final mv = db(c).stock.last;
      expect((mv.type, mv.qtyMilli, mv.batchId), (StockMovementType.restock, Qty.units(6), newer.id));
      expect(db(c).batches.where((b) => b.productId == p.id), hasLength(3), reason: 'no batch created');
      // Batch stock = product stock.
      final ids = {for (final b in db(c).batches.where((b) => b.productId == p.id)) b.id};
      expect(stockWhere(c, (m) => ids.contains(m.batchId)), productStock(c, p.id));
    });

    testWidgets('"+ Batch အသစ်" with batch no. + expiry picked in the calendar → a new batch holding exactly the goods, '
        'sold first at POS by FEFO', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA Amoxicillin R3', expiryAlertDays: 30);
      final b1 = batch(p, 'B1', DateTime.utc(2030, 6, 30));
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [into(p, 2, batchId: b1.id)]);
      await openRestock(tester, c, p);
      await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
      await tester.pumpAndSettle();
      await keys(tester, ['1', '2']);
      final saveBtn = find.descendant(of: find.byType(BottomSheet), matching: find.text('သိမ်းမယ်'));
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('restockBatchNo')), findsOneWidget, reason: 'no batch number: cannot save');
      expect(db(c).batches.where((b) => b.productId == p.id), hasLength(1));

      await tester.enterText(field('restockBatchNo'), 'R3NEW');
      await tester.tap(find.byKey(const ValueKey('restockExpiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('28')));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final expectExpiry = DateTime.utc(now.year, now.month, 28);
      final shown = '${expectExpiry.year}-${expectExpiry.month.toString().padLeft(2, '0')}-28';
      expect(find.descendant(of: find.byKey(const ValueKey('restockExpiry')), matching: find.text(shown)), findsOneWidget);
      final n = kinds(c).length;
      await saveSheet(tester);

      expect(kinds(c).sublist(n), [UnitKind.restock], reason: 'new batch + goods = ONE restock unit');
      final nb = db(c).batches.singleWhere((b) => b.productId == p.id && b.batchNo == 'R3NEW');
      expect(nb.expiryDate, expectExpiry, reason: 'the date picked, as a calendar date');
      expect(stockWhere(c, (m) => m.batchId == nb.id), Qty.units(12));
      expect(stockWhere(c, (m) => m.batchId == b1.id), Qty.units(2));
      expect(productStock(c, p.id), Qty.units(14));

      // POS: two good batches → asked; the new one expires first → listed first; selling it reduces it.
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget);
      expect(tester.getTopLeft(inSheet(find.textContaining('R3NEW'))).dy,
          lessThan(tester.getTopLeft(inSheet(find.textContaining('B1 ·'))).dy));
      expect(inSheet(find.textContaining(shown)), findsOneWidget);
      await tester.tap(inSheet(find.textContaining('R3NEW')));
      await tester.pumpAndSettle();
      await checkoutCash(tester);
      expect(stockWhere(c, (m) => m.batchId == nb.id), Qty.units(11));
    });

    testWidgets('"+ Batch အသစ်" with the number of an existing batch is refused (edit form refuses it too)', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA Dup batch', expiryAlertDays: 30);
      final b1 = batch(p, 'B1', DateTime.utc(2030, 6, 30));
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [into(p, 2, batchId: b1.id)]);
      await openRestock(tester, c, p);
      await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
      await tester.pumpAndSettle();
      await tester.enterText(field('restockBatchNo'), 'B1');
      await keys(tester, ['5']);
      await saveSheet(tester);
      expect(db(c).batches.where((b) => b.productId == p.id && b.batchNo == 'B1'), hasLength(1),
          reason: 'a second batch "B1" makes two identical "B1" rows at POS and in the edit form');
    });

    testWidgets('TC-PROD-06 rule for a batch product: untracked, sold once, first count 20 into a new batch → shows 20',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA Untracked med', expiryAlertDays: 30);
      await c.read(productServiceProvider).create(p); // no stock, no batch: "Stock မမှတ်ရသေး"
      await sell(c, [(productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400)]);
      expect(productStock(c, p.id), -1000);
      await openRestock(tester, c, p);
      await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
      await tester.pumpAndSettle();
      await tester.enterText(field('restockBatchNo'), 'FIRST');
      await keys(tester, ['2', '0']);
      await saveSheet(tester);
      expect(productStock(c, p.id), Qty.units(20),
          reason: 'TC-PROD-05/06: the first count of an untracked product is what was counted (20), not 20 − 1');
    });
  });

  // ================================================================ TC-PROD-NEW-8 restock a size/colour product
  group('TC-PROD-NEW-8 "Stock ဖြည့်မယ်" for a size / colour product (fashion)', () {
    testWidgets('first variant selected by default; chips show "ကျန် n"; goods go to the picked variant; '
        'variant stock adds up to product stock; POS shows the new stock', (tester) async {
      final c = await boot(tester, 'fashion');
      final p = newProduct(c, 'QA ဂျင်း R3');
      final m = variant(p, '30', 'အပြာ'), l = variant(p, '32', 'အနက်');
      await c.read(productServiceProvider).create(p,
          variants: [m, l], initialStock: [into(p, 1, variantId: m.id), into(p, 2, variantId: l.id)]);

      await openRestock(tester, c, p);
      expect(find.descendant(of: find.byKey(ValueKey('restockVariant-${m.id}')), matching: find.textContaining('ကျန် 1')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey('restockVariant-${l.id}')), matching: find.textContaining('ကျန် 2')),
          findsOneWidget);
      await keys(tester, ['3']); // no chip tapped: the first variant
      await saveSheet(tester);
      expect(stockWhere(c, (x) => x.variantId == m.id), Qty.units(4), reason: 'default = first variant');

      await openRestock(tester, c, p);
      await tester.tap(find.byKey(ValueKey('restockVariant-${l.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['5']);
      final n = kinds(c).length;
      await saveSheet(tester);
      expect(kinds(c).sublist(n), [UnitKind.restock]);
      expect(stockWhere(c, (x) => x.variantId == l.id), Qty.units(7));
      expect(stockWhere(c, (x) => x.variantId == m.id), Qty.units(4));
      expect(productStock(c, p.id), Qty.units(11), reason: 'variant stock = product stock');

      await tapInPos(tester, c, p.name);
      expect(inSheet(find.text('ကျန် 4')), findsOneWidget);
      expect(inSheet(find.text('ကျန် 7')), findsOneWidget);
    });

    testWidgets('TC-PROD-06 rule for a variant product: untracked, sold once, first count 20 → shows 20', (tester) async {
      final c = await boot(tester, 'fashion');
      final p = newProduct(c, 'QA Untracked shirt');
      final m = variant(p, 'M', 'အဖြူ');
      await c.read(productServiceProvider).create(p, variants: [m]); // no stock
      await sell(c, [(productId: p.id, variantId: m.id, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400)]);
      await openRestock(tester, c, p);
      await keys(tester, ['2', '0']);
      await saveSheet(tester);
      expect(productStock(c, p.id), Qty.units(20),
          reason: 'TC-PROD-05/06: the first count of an untracked product is what was counted (20), not 20 − 1');
    });
  });

  // ================================================================ TC-PROD-NEW-9 edit form adds, never deletes
  group('TC-PROD-NEW-9 edit form lists and adds IMEIs / batches / sizes — nothing is deleted or changed', () {
    testWidgets('phone: in-stock + sold IMEIs listed; dup of the in-stock one refused, the sold one accepted as a new '
        'in-stock row (trade-in) + two new IMEIs → ONE upsertProduct, +3 stock, old rows identical', (tester) async {
      final c = await boot(tester, 'phone');
      final p = newProduct(c, 'QA Pixel R3');
      final sold = serial(p, '700000000000001', status: SerialStatus.sold);
      final have = serial(p, '700000000000002');
      await c.read(productServiceProvider).create(p, serials: [sold, have], initialStock: [into(p, 1)]);
      final oldRows = db(c).serials.where((s) => s.productId == p.id).map((s) => (s.id, s.serial, s.status, s.updatedAt)).toSet();
      final stock0 = productStock(c, p.id);

      await openEdit(tester, c, p);
      expect(find.text('${sold.serial} · ရောင်းပြီး'), findsOneWidget);
      expect(find.text(have.serial), findsOneWidget);
      Future<void> addImei(String imei) async {
        await tester.enterText(field('newImei'), imei);
        await tester.ensureVisible(find.byKey(const ValueKey('addImei')));
        await tester.tap(find.byKey(const ValueKey('addImei')));
        await tester.pumpAndSettle();
      }

      await addImei('700000000000003');
      await addImei(have.serial); // in stock → still refused
      expect(find.text('ဒီ IMEI ရှိပြီးသားပါ။'), findsOneWidget, reason: 'in-stock ${have.serial} must be refused');
      await addImei(sold.serial); // owner decision 3 (2026-11-14): sold → can be received again (trade-in)
      await addImei('700000000000004');
      expect(find.text('700000000000003 · အသစ်'), findsOneWidget);
      expect(find.text('${sold.serial} · အသစ်'), findsOneWidget, reason: 'the traded-in IMEI is accepted as new');
      expect(find.text('700000000000004 · အသစ်'), findsOneWidget);
      expect(find.text('${have.serial} · အသစ်'), findsNothing);
      final n = kinds(c).length;
      await saveForm(tester);

      expect(kinds(c).sublist(n), [UnitKind.upsertProduct]);
      final rows = db(c).serials.where((s) => s.productId == p.id).toList();
      expect(rows, hasLength(5), reason: 'in-stock dup refused; the sold one received again as a NEW row');
      expect(rows.map((s) => (s.id, s.serial, s.status, s.updatedAt)).toSet().containsAll(oldRows), isTrue,
          reason: 'existing IMEI rows unchanged (the sold history row is kept)');
      final added = rows.where((s) => !oldRows.any((o) => o.$1 == s.id)).map((s) => '${s.serial}/${s.status.name}').toList()
        ..sort();
      expect(added, ['700000000000001/inStock', '700000000000003/inStock', '700000000000004/inStock']);
      expect(productStock(c, p.id), stock0 + Qty.units(3), reason: 'each new IMEI = one phone in hand');
    });

    testWidgets('pharmacy: batches listed (expiry, stock, expired badge, empty one); new batch with expiry starts empty; '
        'old batch rows identical; restock then offers it', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = newProduct(c, 'QA Vitamin C R3', expiryAlertDays: 30);
      final exp = batch(p, 'OLD19', DateTime.utc(2019, 1, 31));
      final empty = batch(p, 'EMPTY', DateTime.utc(2029, 1, 31));
      final good = batch(p, 'GOOD', DateTime.utc(2030, 1, 31));
      await c.read(productServiceProvider).create(p,
          batches: [exp, empty, good], initialStock: [into(p, 3, batchId: exp.id), into(p, 4, batchId: good.id)]);
      final old = db(c).batches.where((b) => b.productId == p.id).map((b) => (b.id, b.batchNo, b.expiryDate, b.updatedAt, b.deletedAt)).toSet();
      final stock0 = productStock(c, p.id);

      await openEdit(tester, c, p);
      Finder row(ProductBatch b) => find.byKey(ValueKey('batch-${b.id}'));
      expect(find.descendant(of: row(exp), matching: find.text(ExpiredBadge.label)), findsOneWidget);
      expect(find.descendant(of: row(good), matching: find.text(ExpiredBadge.label)), findsNothing);
      expect(find.descendant(of: row(exp), matching: find.text('ကျန် 3')), findsOneWidget);
      expect(find.descendant(of: row(empty), matching: find.text('ကျန် 0')), findsOneWidget, reason: 'empty batch still listed');
      expect(find.descendant(of: row(good), matching: find.textContaining('2030-01-31')), findsOneWidget);

      await tester.enterText(field('newBatchNo'), 'EDITNEW');
      await tester.ensureVisible(find.byKey(const ValueKey('newBatchExpiry')));
      await tester.tap(find.byKey(const ValueKey('newBatchExpiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('27')));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('addBatch')));
      await tester.tap(find.byKey(const ValueKey('addBatch')));
      await tester.pumpAndSettle();
      final n = kinds(c).length;
      await saveForm(tester);

      expect(kinds(c).sublist(n), [UnitKind.upsertProduct]);
      final all = db(c).batches.where((b) => b.productId == p.id).toList();
      expect(all.map((b) => (b.id, b.batchNo, b.expiryDate, b.updatedAt, b.deletedAt)).toSet().containsAll(old), isTrue,
          reason: 'expired / empty / good batches kept unchanged');
      final nb = all.singleWhere((b) => b.batchNo == 'EDITNEW');
      expect(nb.expiryDate, DateTime.utc(now.year, now.month, 27));
      expect(stockWhere(c, (m) => m.batchId == nb.id), 0, reason: 'a new batch starts empty');
      expect(productStock(c, p.id), stock0, reason: 'no stock written by adding a batch');

      await openRestock(tester, c, p);
      expect(find.byKey(ValueKey('restockBatch-${nb.id}')), findsOneWidget, reason: 'goods can now go into it');
    });

    testWidgets('fashion: variants listed with stock; new size/colour starts empty; old ones unchanged; POS lists it',
        (tester) async {
      final c = await boot(tester, 'fashion');
      final p = newProduct(c, 'QA Polo R3');
      final m = variant(p, 'M', 'အနက်');
      await c.read(productServiceProvider).create(p, variants: [m], initialStock: [into(p, 3, variantId: m.id)]);
      final stock0 = productStock(c, p.id);
      await openEdit(tester, c, p);
      expect(find.descendant(of: find.byKey(ValueKey('variant-${m.id}')), matching: find.text('ကျန် 3')), findsOneWidget);
      await tester.enterText(field('newVariantSize'), 'XL');
      await tester.enterText(field('newVariantColor'), 'အနီ');
      await tester.ensureVisible(find.byKey(const ValueKey('addVariant')));
      await tester.tap(find.byKey(const ValueKey('addVariant')));
      await tester.pumpAndSettle();
      await saveForm(tester);
      final vs = db(c).variants.where((v) => v.productId == p.id).toList();
      expect(vs.map((v) => v.label).toSet(), {'M · အနက်', 'XL · အနီ'});
      expect(vs.singleWhere((v) => v.id == m.id).updatedAt, t0, reason: 'old variant row unchanged');
      expect(productStock(c, p.id), stock0);
      await tapInPos(tester, c, p.name);
      expect(inSheet(find.textContaining('XL')), findsOneWidget);
      expect(inSheet(find.text('ကျန် 0')), findsOneWidget);
    });

    testWidgets('an IMEI typed in the edit form but not "+ ထည့်"-ed is not silently lost on save', (tester) async {
      final c = await boot(tester, 'phone');
      final p = newProduct(c, 'QA Typed IMEI');
      await c.read(productServiceProvider).create(p, serials: [serial(p, '800000000000001')], initialStock: [into(p, 1)]);
      await openEdit(tester, c, p);
      await tester.enterText(field('newImei'), '800000000000002');
      await tester.pumpAndSettle();
      await saveForm(tester);
      final saved = db(c).serials.any((s) => s.serial == '800000000000002');
      final warned = find.text('ပစ္စည်း ပြင်မယ်').evaluate().isNotEmpty; // still on the form (e.g. with a warning)
      expect(saved || warned, isTrue,
          reason: 'the restock sheet takes a typed IMEI on save; here it vanished without a word (stock not +1)');
    });
  });

  // ================================================================ TC-POS-NEW-5 expired batches at POS
  group('TC-POS-NEW-5 expired batches at POS', () {
    testWidgets('the expiry day itself is still sellable: the only batch with stock expiring TODAY is auto-picked',
        (tester) async {
      final c = await boot(tester, 'pharmacy', height: 844);
      final p = newProduct(c, 'QA Today', expiryAlertDays: 30);
      final b = batch(p, 'TODAY', today);
      final y = batch(p, 'YDAY', today.subtract(const Duration(days: 1)));
      await c.read(productServiceProvider).create(p, batches: [b, y], initialStock: [into(p, 2, batchId: b.id), into(p, 2, batchId: y.id)]);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsNothing, reason: 'one unexpired batch with stock: taken without asking');
      expect(find.textContaining('သက်တမ်းကုန်နေပါပြီ'), findsNothing, reason: 'no confirm for the expiry day');
      expect(c.read(cartProvider).lines.single.batchId, b.id, reason: 'yesterday\'s batch is expired, never auto-picked');
    });

    testWidgets('expired YESTERDAY + nothing else: asked, red badge, barrier-dismissing the confirm = cancel; '
        '"သိပြီး ရောင်းမယ်" sells from it and the sale line carries it', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 844);
      final p = newProduct(c, 'QA Yesterday', expiryAlertDays: 30);
      final y = batch(p, 'YDAY', today.subtract(const Duration(days: 1)));
      await c.read(productServiceProvider).create(p, batches: [y], initialStock: [into(p, 3, batchId: y.id)]);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget);
      expect(inSheet(find.text(ExpiredBadge.label)), findsOneWidget);
      final title = tester.widget<Text>(inSheet(find.textContaining('YDAY')));
      expect(title.style?.color, isNot(tester.widget<Text>(find.text('ဘယ် Batch လဲ?')).style?.color),
          reason: 'expired title drawn in the danger colour');
      await tester.tap(inSheet(find.textContaining('YDAY')));
      await tester.pumpAndSettle();
      expect(find.textContaining('သက်တမ်းကုန်နေပါပြီ'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // outside the dialog
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines, isEmpty, reason: 'dismissed confirm = not sold');

      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.textContaining('YDAY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sellExpired')));
      await tester.pumpAndSettle();
      await checkoutCash(tester);
      final line = db(c).sales.expand((s) => s.lines).singleWhere((l) => l.productId == p.id);
      expect(line.batchId, y.id);
      expect(stockWhere(c, (m) => m.batchId == y.id), Qty.units(2));
    });

    testWidgets('two good + one expired (earliest date): good ones by FEFO first, expired last with the only badge; '
        'a good pick needs no confirm', (tester) async {
      final c = await boot(tester, 'pharmacy', height: 844);
      final p = newProduct(c, 'QA Mixed', expiryAlertDays: 30);
      final e = batch(p, 'E-OLD', DateTime.utc(2021, 1, 1));
      final g1 = batch(p, 'G-2029', DateTime.utc(2029, 1, 1));
      final g2 = batch(p, 'G-2028', DateTime.utc(2028, 1, 1));
      await c.read(productServiceProvider).create(p,
          batches: [e, g1, g2], initialStock: [into(p, 1, batchId: e.id), into(p, 1, batchId: g1.id), into(p, 1, batchId: g2.id)]);
      await tapInPos(tester, c, p.name);
      double y(String s) => tester.getTopLeft(inSheet(find.textContaining(s))).dy;
      expect(y('G-2028'), lessThan(y('G-2029')));
      expect(y('G-2029'), lessThan(y('E-OLD')), reason: 'expired listed after the good ones even though it expires first');
      expect(inSheet(find.text(ExpiredBadge.label)), findsOneWidget);
      await tester.tap(inSheet(find.textContaining('G-2028')));
      await tester.pumpAndSettle();
      expect(find.textContaining('သက်တမ်းကုန်နေပါပြီ'), findsNothing);
      expect(c.read(cartProvider).lines.single.batchId, g2.id);
    });
  });

  // ================================================================ TC-PROD-NEW-10 cleared low-stock alert
  group('TC-PROD-NEW-10 edit form: clearing "နည်းရင် သတိပေး" = no alert (0)', () {
    testWidgets('hardware 2.5 ပေ alert cleared → 0, not "low" any more, field empty on reopen; then 0.75 → 750', (tester) async {
      final c = await boot(tester, 'hardware');
      final p = newProduct(c, 'QA ကြိုး R3', lowAlertMilli: 2500, unit: 'ပေ');
      await c.read(productServiceProvider).create(p, initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: 2000, note: 'initial'),
      ]);
      await tester.pumpAndSettle();
      expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).isLow, isTrue);
      await openEdit(tester, c, p);
      expect((field('lowAlert').evaluate().single.widget as EditableText).controller.text, '2.5');
      await tester.enterText(field('lowAlert'), '');
      final n = kinds(c).length;
      await saveForm(tester);
      expect(kinds(c).sublist(n), [UnitKind.upsertProduct]);
      expect(db(c).products.firstWhere((x) => x.id == p.id).lowAlertMilli, 0);
      expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).isLow, isFalse);

      await openEdit(tester, c, p);
      expect((field('lowAlert').evaluate().single.widget as EditableText).controller.text, '', reason: '0 shows as an empty field');
      await tester.enterText(field('lowAlert'), '0.75');
      await saveForm(tester);
      expect(db(c).products.firstWhere((x) => x.id == p.id).lowAlertMilli, 750);
    });
  });
}
