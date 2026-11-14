import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// BUG-2: POS asks which IMEI / size-colour / batch and the cart carries it.
void main() {
  setUpAll(loadAppFonts);

  Product product(String tenantId, String name) {
    final t = nowUtc();
    return Product(
      id: newId(), tenantId: tenantId, name: name, cost: 100, price: 1000,
      category: 'အထွေထွေ', tint: 0xFFDBEAFE, initial: name.characters.first, createdAt: t, updatedAt: t,
      expiryAlertDays: 30, // medicines track expiry (only matters with the Batch feature on)
    );
  }

  Future<ProviderContainer> boot(WidgetTester tester, String template) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
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

  testWidgets('phone: the IMEI sheet offers in-stock IMEIs not already in the cart; one IMEI = one unit',
      (tester) async {
    final c = await boot(tester, 'phone');
    final tenantId = c.read(tenantIdProvider);
    final p = product(tenantId, 'QA Redmi');
    final t = nowUtc();
    ProductSerial s(String imei, SerialStatus st) => ProductSerial(
        id: newId(), tenantId: tenantId, productId: p.id, serial: imei, status: st, createdAt: t, updatedAt: t);
    final a = s('111111111111111', SerialStatus.inStock);
    final b = s('222222222222222', SerialStatus.inStock);
    final sold = s('333333333333333', SerialStatus.sold);
    await c.read(productServiceProvider).create(p, serials: [a, b, sold]);

    await tapInPos(tester, c, p.name);
    expect(find.text('ဘယ် IMEI လဲ?'), findsOneWidget);
    expect(find.text(sold.serial), findsNothing, reason: 'sold IMEIs are not offered');
    await tester.tap(find.text(b.serial));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines.single.serialId, b.id);
    expect(c.read(cartProvider).lines.single.name, contains(b.serial));

    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    expect(find.text(b.serial), findsNothing, reason: 'already in the cart');
    await tester.tap(find.text(a.serial));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).serialIds, {a.id, b.id});

    // Every IMEI is in the cart now: nothing left to offer, nothing added.
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းစရာ IMEI မကျန်တော့ပါ'), findsOneWidget);
    await tester.tapAt(const Offset(195, 50)); // dismiss
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines, hasLength(2));

    // A serial line's quantity never goes above 1.
    final key = c.read(cartProvider).lines.first.key;
    c.read(cartProvider.notifier).setQty(key, Qty.units(3));
    expect(c.read(cartProvider).qtyOf(key), Qty.units(1));
  });

  testWidgets('pharmacy: several batches → asked, earliest expiry first; one batch with stock → taken without asking',
      (tester) async {
    final c = await boot(tester, 'pharmacy');
    final tenantId = c.read(tenantIdProvider);
    final p = product(tenantId, 'QA Amoxicillin');
    final t = nowUtc();
    ProductBatch batch(String no, DateTime? exp) => ProductBatch(
        id: newId(), tenantId: tenantId, productId: p.id, batchNo: no, qtyMilli: Qty.units(10),
        expiryDate: exp, createdAt: t, updatedAt: t);
    final late = batch('LATE', DateTime.utc(2028, 1, 1));
    final early = batch('EARLY', DateTime.utc(2027, 1, 1));
    StockMovement into(ProductBatch b, int units) =>
        restockMovement(tenantId: tenantId, productId: p.id, qtyMilli: Qty.units(units), batchId: b.id, note: 'initial');
    await c.read(productServiceProvider).create(p, batches: [late, early], initialStock: [into(late, 10), into(early, 10)]);

    await tapInPos(tester, c, p.name);
    expect(find.text('ဘယ် Batch လဲ?'), findsOneWidget);
    double y(String s) => tester.getTopLeft(find.textContaining(s)).dy;
    expect(y('EARLY'), lessThan(y('LATE')), reason: 'FEFO: earliest expiry on top');
    await tester.tap(find.textContaining('EARLY'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines.single.batchId, early.id);

    // Same batch again adds to its line.
    await tester.tap(find.text(p.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('EARLY'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).lines.single.qtyMilli, Qty.units(2));

    // A product with only one batch in stock: no question.
    final q = product(tenantId, 'QA Vitamin C');
    final only = ProductBatch(id: newId(), tenantId: tenantId, productId: q.id, batchNo: 'V1', qtyMilli: Qty.units(5),
        createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(q, batches: [only],
        initialStock: [restockMovement(tenantId: tenantId, productId: q.id, qtyMilli: Qty.units(5), batchId: only.id, note: 'initial')]);
    await tapInPos(tester, c, q.name);
    expect(find.text('ဘယ် Batch လဲ?'), findsNothing);
    expect(c.read(cartProvider).lines.firstWhere((l) => l.productId == q.id).batchId, only.id);
  });

  test('toDrafts carries variant / batch / serial ids', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    final p = product('t', 'x');
    c.read(cartProvider.notifier)
      ..addProduct(p, pick: (variantId: 'v1', batchId: null, serialId: null, label: 'M · အနက်'))
      ..addProduct(p, pick: (variantId: null, batchId: 'b1', serialId: null, label: 'Batch B1'))
      ..addProduct(p, pick: (variantId: null, batchId: null, serialId: 's1', label: 'IMEI 1'));
    final d = c.read(cartProvider).toDrafts();
    expect([for (final x in d) (x.variantId, x.batchId, x.serialId)], [('v1', null, null), (null, 'b1', null), (null, null, 's1')]);
    expect(c.read(cartProvider).qtyOfProduct(p.id), Qty.units(3));
    expect(d.first.name, 'x · M · အနက်');
  });
}
