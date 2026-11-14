import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/inventory/presentation/restock_sheet.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';

/// BUG-12 (restock / edit follow the product's modules), expired batches at
/// POS, and clearing the low-stock alert.
void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, String template) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  List<UnitKind> kinds(ProviderContainer c) => (c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds;
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  int stockWhere(ProviderContainer c, bool Function(StockMovement) f) =>
      db(c).stock.where((m) => m.deletedAt == null && f(m)).fold(0, (a, m) => a + m.qtyMilli);

  Product product(ProviderContainer c, String name, {int lowAlertMilli = 5000}) {
    final t = nowUtc();
    return Product(
      id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
      tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t, lowAlertMilli: lowAlertMilli,
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

  group('BUG-12 "Stock ဖြည့်မယ်" follows the product', () {
    testWidgets('phone: a list of IMEIs (typed / scanned); duplicates refused; count = list size; ONE restock unit',
        (tester) async {
      final c = await boot(tester, 'phone');
      final p = product(c, 'QA Note 14');
      final t = nowUtc();
      final old = ProductSerial(id: newId(), tenantId: p.tenantId, productId: p.id, serial: '111111111111111',
          status: SerialStatus.sold, createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, serials: [old]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();

      for (final imei in ['222222222222222', '111111111111111', '333333333333333']) {
        await tester.enterText(field('imei'), imei);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      expect(inSheet(find.text('ဒီ IMEI ရှိပြီးသားပါ။')), findsNothing, reason: 'the last one was valid');
      expect(inSheet(find.textContaining('IMEI 2 လုံး')), findsOneWidget, reason: '111… already exists (sold)');
      final n = kinds(c).length;
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();

      // The product has no stock history yet ("Stock မမှတ်ရသေး"): its first count is an opening count (BUG-15).
      expect(kinds(c).sublist(n), [UnitKind.stockAdjust]);
      final fresh = db(c).serials.where((s) => s.productId == p.id && s.status == SerialStatus.inStock).map((s) => s.serial);
      expect(fresh.toSet(), {'222222222222222', '333333333333333'});
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(2));
      expect(db(c).serials.where((s) => s.id == old.id).single.status, SerialStatus.sold, reason: 'sold one untouched');
    });

    testWidgets('pharmacy: default = newest unexpired batch; "+ Batch အသစ်" creates a batch (no. + expiry) holding the goods',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA Ibuprofen');
      final t = nowUtc();
      final b1 = ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'B1', qtyMilli: 0,
          expiryDate: DateTime.utc(2030, 1, 31), createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, batchId: b1.id, qtyMilli: Qty.units(2)),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
      await tester.pumpAndSettle();
      await tester.enterText(field('restockBatchNo'), 'B2');
      await tester.tap(find.byKey(const ValueKey('restockExpiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await keys(tester, ['2', '0']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();

      final b2 = db(c).batches.singleWhere((b) => b.productId == p.id && b.batchNo == 'B2');
      expect(b2.expiryDate, isNotNull);
      expect(stockWhere(c, (m) => m.batchId == b2.id), Qty.units(20));
      expect(stockWhere(c, (m) => m.batchId == b1.id), Qty.units(2));
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(22), reason: 'batch stock = product stock');
    });

    testWidgets('fashion: pick the size/colour the goods belong to', (tester) async {
      final c = await boot(tester, 'fashion');
      final p = product(c, 'QA ရှပ် R3');
      final t = nowUtc();
      ProductVariant v(String s, String col) =>
          ProductVariant(id: newId(), tenantId: p.tenantId, productId: p.id, size: s, color: col, createdAt: t, updatedAt: t);
      final m = v('M', 'အနက်'), l = v('L', 'အဖြူ');
      await c.read(productServiceProvider).create(p, variants: [m, l]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('restockVariant-${l.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['4']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(stockWhere(c, (x) => x.variantId == l.id), Qty.units(4));
      expect(stockWhere(c, (x) => x.variantId == m.id), 0);
    });
  });

  test('Drift: receive() = ONE restock unit carrying the new IMEI / batch rows and the movement', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA D', cost: 1, price: 2, category: 'x', tint: 0,
        initial: 'D', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p);
    await adb.delete(adb.outbox).go();

    final stock = c.read(stockServiceProvider);
    await stock.receive(productId: p.id, qtyMilli: Qty.units(2), serials: ['777777777777777', '888888888888888']);
    final nb = ProductBatch(id: newId(), tenantId: shop.tenantId, productId: p.id, batchNo: 'DB1', qtyMilli: Qty.units(6),
        expiryDate: DateTime.utc(2030, 1, 1), createdAt: t, updatedAt: t);
    await stock.receive(productId: p.id, qtyMilli: Qty.units(6), newBatch: nb);
    expect(() => stock.receive(productId: p.id, qtyMilli: Qty.units(3), serials: ['1']), throwsArgumentError,
        reason: 'IMEI count must equal the quantity');

    final units = await outbox(adb);
    expect(units.map((u) => u.kind), ['restock', 'restock']);
    final r1 = SyncStore.rowsOf(units[0]);
    expect((r1[WireTable.productSerials] as List).length, 2);
    expect(((r1[WireTable.stockMovements] as List).single as Map)['qtyMilli'], 2000);
    final r2 = SyncStore.rowsOf(units[1]);
    expect(((r2[WireTable.productBatches] as List).single as Map)['batchNo'], 'DB1');
    expect(((r2[WireTable.stockMovements] as List).single as Map)['batchId'], nb.id);
  });

  group('BUG-12 edit form lists and adds IMEIs / batches / sizes-colours (never deletes)', () {
    testWidgets('phone: existing IMEIs listed (sold marked); a new IMEI = new in-stock row + stock +1, in the upsertProduct unit',
        (tester) async {
      final c = await boot(tester, 'phone');
      final p = product(c, 'QA Pixel');
      final t = nowUtc();
      final sold = ProductSerial(id: newId(), tenantId: p.tenantId, productId: p.id, serial: '444444444444444',
          status: SerialStatus.sold, createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, serials: [sold]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      expect(find.text('444444444444444 · ရောင်းပြီး'), findsOneWidget);

      await tester.enterText(field('newImei'), '555555555555555');
      await tester.tap(find.byKey(const ValueKey('addImei')));
      await tester.pumpAndSettle();
      expect(find.text('555555555555555 · အသစ်'), findsOneWidget);
      final n = kinds(c).length;
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();

      expect(kinds(c).sublist(n), [UnitKind.upsertProduct]);
      expect(db(c).serials.where((s) => s.productId == p.id).map((s) => (s.serial, s.status)).toSet(),
          {('444444444444444', SerialStatus.sold), ('555555555555555', SerialStatus.inStock)});
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(1));
    });

    testWidgets('pharmacy + fashion rows: new batch (empty) and new size/colour (empty) are added; existing kept',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA Vitamin B');
      final t = nowUtc();
      final b1 = ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'VB1', qtyMilli: 0,
          expiryDate: DateTime.utc(2020, 1, 1), createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, batches: [b1], initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, batchId: b1.id, qtyMilli: Qty.units(3)),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(ValueKey('batch-${b1.id}')), matching: find.text(ExpiredBadge.label)),
          findsOneWidget, reason: 'an expired batch is marked red in the list');
      await tester.enterText(field('newBatchNo'), 'VB2');
      await tester.tap(find.byKey(const ValueKey('addBatch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      final batches = db(c).batches.where((b) => b.productId == p.id).map((b) => b.batchNo).toSet();
      expect(batches, {'VB1', 'VB2'});
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(3), reason: 'a new batch starts empty');

      // Fashion: a new size · colour.
      c.read(shopTemplateProvider.notifier).select('fashion');
      final q = product(c, 'QA Polo');
      final m = ProductVariant(id: newId(), tenantId: q.tenantId, productId: q.id, size: 'M', color: 'အနက်', createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(q, variants: [m]);
      await openProducts(tester, c, q.name);
      await tester.tap(find.text(q.name).last);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('variant-${m.id}')), findsOneWidget);
      await tester.enterText(field('newVariantSize'), 'XL');
      await tester.enterText(field('newVariantColor'), 'အပြာ');
      await tester.tap(find.byKey(const ValueKey('addVariant')));
      await tester.pumpAndSettle();
      await tester.enterText(field('newVariantSize'), 'M');
      await tester.enterText(field('newVariantColor'), 'အနက်');
      await tester.tap(find.byKey(const ValueKey('addVariant')));
      await tester.pumpAndSettle();
      expect(find.text('ဒီ Size / အရောင် ရှိပြီးသားပါ။'), findsOneWidget);
      // BUG-17: the refused size/colour is still typed → save is blocked, nothing written.
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget, reason: 'still on the form');
      expect(db(c).variants.where((v) => v.productId == q.id), hasLength(1));
      await tester.enterText(field('newVariantSize'), '');
      await tester.enterText(field('newVariantColor'), '');
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(db(c).variants.where((v) => v.productId == q.id).map((v) => v.label).toSet(), {'M · အနက်', 'XL · အပြာ'});
    });
  });

  group('expired batches at POS', () {
    Future<(ProviderContainer, Product, ProductBatch, ProductBatch?)> setup(WidgetTester tester, {bool withGood = false}) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA Expiring');
      final t = nowUtc();
      final old = ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'OLD', qtyMilli: 0,
          expiryDate: DateTime.utc(2020, 6, 30), createdAt: t, updatedAt: t);
      final good = withGood
          ? ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'GOOD', qtyMilli: 0,
              expiryDate: DateTime.utc(2099, 1, 1), createdAt: t, updatedAt: t)
          : null;
      await c.read(productServiceProvider).create(p, batches: [old, ?good], initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, batchId: old.id, qtyMilli: Qty.units(5)),
        if (good != null) restockMovement(tenantId: p.tenantId, productId: p.id, batchId: good.id, qtyMilli: Qty.units(5)),
      ]);
      return (c, p, old, good);
    }

    testWidgets('the only batch with stock is expired: NOT auto-picked; red "သက်တမ်းကုန်"; cancel = nothing; confirm = sold',
        (tester) async {
      final (c, p, old, _) = await setup(tester);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget, reason: 'never auto-picked');
      expect(inSheet(find.text(ExpiredBadge.label)), findsOneWidget);
      expect(c.read(cartProvider).lines, isEmpty);

      await tester.tap(inSheet(find.textContaining('OLD')));
      await tester.pumpAndSettle();
      expect(find.textContaining('သက်တမ်းကုန်နေပါပြီ'), findsOneWidget, reason: 'explicit confirm');
      await tester.tap(find.text('မရောင်းတော့ပါ'));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines, isEmpty, reason: 'cancel adds nothing');

      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.textContaining('OLD')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sellExpired')));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.batchId, old.id);
    });

    testWidgets('one good + one expired batch: the good one is taken without asking', (tester) async {
      final (c, p, _, good) = await setup(tester, withGood: true);
      await tapInPos(tester, c, p.name);
      expect(find.text('ဘယ် Batch လဲ?'), findsNothing);
      expect(c.read(cartProvider).lines.single.batchId, good!.id);
    });

    test('isExpired: past day = expired; the expiry day itself and undated = not', () {
      final t = DateTime.utc(2026, 1, 1);
      ProductBatch b(DateTime? e) =>
          ProductBatch(id: 'b', tenantId: 't', productId: 'p', batchNo: 'x', qtyMilli: 0, expiryDate: e, createdAt: t, updatedAt: t);
      final now = DateTime(2026, 11, 14, 12);
      expect(b(DateTime.utc(2026, 11, 13)).isExpired(now), isTrue);
      expect(b(DateTime.utc(2026, 11, 14)).isExpired(now), isFalse);
      expect(b(null).isExpired(now), isFalse);
    });
  });

  testWidgets('edit form: clearing the low-stock alert saves "no alert" (0), and the product is no longer "low"',
      (tester) async {
    final c = await boot(tester, 'grocery');
    final p = product(c, 'QA Alert', lowAlertMilli: Qty.units(10));
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(3)),
    ]);
    await tester.pumpAndSettle();
    expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).isLow, isTrue);
    await openProducts(tester, c, p.name);
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    await tester.enterText(field('lowAlert'), '');
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    expect(db(c).products.firstWhere((x) => x.id == p.id).lowAlertMilli, 0);
    expect(c.read(productsProvider).requireValue.firstWhere((x) => x.id == p.id).isLow, isFalse);

    // Opening it again shows the field empty (not "0").
    await openProducts(tester, c, p.name);
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    expect((field('lowAlert').evaluate().single.widget as EditableText).controller.text, '');
  });
}
