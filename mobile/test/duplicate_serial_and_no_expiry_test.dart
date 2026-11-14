import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sync/domain/sync_labels.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';
import 'sync_screens_test.dart' show settle;

/// Item 4 (BUG-18 decision): an IMEI already known on this phone (any product)
/// is refused; the server's duplicateSerial issue shows in "စစ်ရန်".
/// Item 5 (pharmacy decision): batches only for products that track expiry.
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
  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);
  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  int stockWhere(ProviderContainer c, bool Function(StockMovement) f) =>
      db(c).stock.where((m) => m.deletedAt == null && f(m)).fold(0, (a, m) => a + m.qtyMilli);

  Product product(ProviderContainer c, String name, {int? expiryDays}) {
    final t = nowUtc();
    return Product(
      id: newId(), tenantId: c.read(tenantIdProvider), name: name, cost: 400, price: 600, category: 'QA',
      tint: 0, initial: 'Q', createdAt: t, updatedAt: t, expiryAlertDays: expiryDays,
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

  // ================================================================ item 4
  group('item 4: an IMEI the phone already knows (any product) is refused', () {
    Future<(ProviderContainer, Product, Product)> twoPhones(WidgetTester tester) async {
      final c = await boot(tester, 'phone');
      final a = product(c, 'QA Phone A'), b = product(c, 'QA Phone B');
      final t = nowUtc();
      await c.read(productServiceProvider).create(a, serials: [
        ProductSerial(id: newId(), tenantId: a.tenantId, productId: a.id, serial: '990000000000001',
            status: SerialStatus.inStock, createdAt: t, updatedAt: t),
      ], initialStock: [restockMovement(tenantId: a.tenantId, productId: a.id, qtyMilli: Qty.units(1))]);
      await c.read(productServiceProvider).create(b, serials: [
        ProductSerial(id: newId(), tenantId: b.tenantId, productId: b.id, serial: '990000000000002',
            status: SerialStatus.inStock, createdAt: t, updatedAt: t),
      ], initialStock: [restockMovement(tenantId: b.tenantId, productId: b.id, qtyMilli: Qty.units(1))]);
      return (c, a, b);
    }

    testWidgets('"Stock ဖြည့်မယ်": IMEI of another product refused', (tester) async {
      final (c, _, b) = await twoPhones(tester);
      await openProducts(tester, c, b.name);
      await tester.tap(find.byKey(ValueKey('restock-${b.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(field('imei'), '990000000000001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('ဒီ IMEI ရှိပြီးသားပါ။')), findsOneWidget);
      expect(inSheet(find.textContaining('IMEI 0 လုံး')), findsOneWidget);
    });

    testWidgets('edit form: IMEI of another product refused, and the typed refused IMEI blocks save', (tester) async {
      final (c, _, b) = await twoPhones(tester);
      await openProducts(tester, c, b.name);
      await tester.tap(find.text(b.name).last);
      await tester.pumpAndSettle();
      await tester.enterText(field('newImei'), '990000000000001');
      await tester.tap(find.byKey(const ValueKey('addImei')));
      await tester.pumpAndSettle();
      expect(find.text('ဒီ IMEI ရှိပြီးသားပါ။'), findsOneWidget);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget, reason: 'save blocked, never silently dropped');
      expect(db(c).serials.where((s) => s.serial == '990000000000001'), hasLength(1));
    });

    testWidgets('Add Product: IMEI of an existing product refused', (tester) async {
      final (c, _, _) = await twoPhones(tester);
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.enterText(field('imei'), '990000000000002');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('ဒီ IMEI ရှိပြီးသားပါ။'), findsOneWidget);
    });

    test('"စစ်ရန်" title for the server issue kind', () {
      expect(issueKindLabel('duplicateSerial'), isNot('duplicateSerial'));
      expect(issueKindLabel('duplicateSerial'), contains('IMEI'));
    });

    testWidgets('a pulled duplicateSerial issue is listed in "စစ်ရန်"', (tester) async {
      final adb = memoryDb();
      addTearDown(() => tester.runAsync(adb.close));
      final api = FakeSyncApi();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (c, shop) = (await tester.runAsync(() => driftContainer(adb, overrides: [
            syncApiProvider.overrideWithValue(api),
            connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          ])))!;
      addTearDown(c.dispose);
      final store = SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId);
      final t = nowUtc().toIso8601String();
      await tester.runAsync(() async {
        await store.markInitialSyncDone();
        await store.mergePage(page({
          'syncIssues': [
            {
              'id': newId(), 'tenantId': shop.tenantId, 'kind': 'duplicateSerial', 'entityTable': 'ProductSerials',
              'entityId': newId(), 'detail': 'Serial 351111111111111 is already in stock (QA). Both rows were kept.',
              'createdAt': t, 'updatedAt': t,
            },
          ],
        }, cursor: '1'));
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await settle(tester);
      c.read(appRouterProvider).go(Routes.syncReview);
      await settle(tester);
      expect(find.text(issueKindLabel('duplicateSerial')), findsOneWidget);
      expect(await tester.runAsync(() => adb.select(adb.syncIssues).get()), hasLength(1));
    });
  });

  // ================================================================ item 5
  group('item 5: pharmacy — batches only for products that track expiry', () {
    testWidgets('Add Product: "သက်တမ်း မမှတ်ပါ" hides batch fields, saves no expiryAlertDays and no batch', (tester) async {
      final c = await boot(tester, 'pharmacy');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expiryHelp')), findsOneWidget, reason: 'the form explains the rule');
      expect(find.byKey(const ValueKey('batchNo')), findsOneWidget, reason: 'tracked by default');
      await tester.tap(find.byKey(const ValueKey('expiryWarn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('သက်တမ်း မမှတ်ပါ').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batchNo')), findsNothing);
      await tester.enterText(field('productName'), 'QA ဆပ်ပြာ');
      await tester.enterText(field('price'), '1500');
      await tester.enterText(field('stockQty'), '12');
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      final p = db(c).products.firstWhere((x) => x.name == 'QA ဆပ်ပြာ');
      expect(p.expiryAlertDays, isNull);
      expect(db(c).batches.where((b) => b.productId == p.id), isEmpty);
      expect(stockWhere(c, (m) => m.productId == p.id && m.batchId == null), Qty.units(12));
    });

    testWidgets('no-expiry product: restock defaults to "Batch မပါ" (goods without batch); POS sells it without asking',
        (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA ဒိုင်ပါ');
      await c.read(productServiceProvider).create(p, initialStock: [
        restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(3)),
      ]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      final none = find.byKey(const ValueKey('restockBatch-none'));
      expect(none, findsOneWidget);
      expect(tester.widget<Semantics>(find.ancestor(of: none, matching: find.byType(Semantics)).first).properties.selected,
          isTrue, reason: 'default: no batch');
      await keys(tester, ['5']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(db(c).stock.last.batchId, isNull);
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(8));

      c.read(appRouterProvider).go(Routes.pos);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, p.name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      expect(find.text('ဘယ် Batch လဲ?'), findsNothing);
      expect(c.read(cartProvider).lines.single.batchId, isNull);
    });

    testWidgets('no-expiry product, untracked, sold once: first count 20 with "Batch မပါ" shows 20', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA ဆပ်ပြာခဲ');
      await c.read(productServiceProvider).create(p);
      await sell(c, [(productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 600, cost: 400)]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      await keys(tester, ['2', '0']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(stockWhere(c, (m) => m.productId == p.id), Qty.units(20));
    });

    testWidgets('expiry-tracked product: no "Batch မပါ" — a batch is required', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA Amox tracked', expiryDays: 30);
      await c.read(productServiceProvider).create(p);
      await openProducts(tester, c, p.name);
      await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('restockBatch-none')), findsNothing);
      await keys(tester, ['5']);
      await tester.tap(inSheet(find.text('သိမ်းမယ်')));
      await tester.pumpAndSettle();
      expect(db(c).stock.where((m) => m.productId == p.id), isEmpty, reason: 'no batch no. yet: cannot save');
    });

    testWidgets('edit: switching a product to "သက်တမ်း မမှတ်ပါ" clears expiryAlertDays; existing batches stay', (tester) async {
      final c = await boot(tester, 'pharmacy');
      final p = product(c, 'QA switch', expiryDays: 60);
      final t = nowUtc();
      final b = ProductBatch(id: newId(), tenantId: p.tenantId, productId: p.id, batchNo: 'S1', qtyMilli: 0,
          expiryDate: DateTime.utc(2030, 1, 1), createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p, batches: [b]);
      await openProducts(tester, c, p.name);
      await tester.tap(find.text(p.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expiryWarn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('သက်တမ်း မမှတ်ပါ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(db(c).products.firstWhere((x) => x.id == p.id).expiryAlertDays, isNull);
      expect(db(c).batches.where((x) => x.productId == p.id), hasLength(1));
    });
  });
}
