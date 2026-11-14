// QA round 5 — Drift (real local database, in memory): owner decision 3 (trade-in) at the SQL / outbox level.
// "an IMEI whose last status is 'sold' can be received again (new inStock row, history kept); an IMEI that is 'inStock'
// is still refused" (f5b6e3b: ProductRepository.watchInStockSerialValues).
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1);

  test('TC-PROD-NEW-25 Drift: in-stock IMEI set (SQL) excludes sold / deleted; trade-in = ONE restock unit with only the NEW '
      'row (sold row not re-sent, unchanged); void of the original sale recorded for TC-PROD-NEW-26 (not asserted)', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final repo = c.read(productRepositoryProvider);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R5 D trade-in', cost: 1, price: 2, category: 'x',
        tint: 0, initial: 'D', createdAt: t0, updatedAt: t0);
    final x = ProductSerial(id: newId(), tenantId: shop.tenantId, productId: p.id, serial: '354000000000001',
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
    final gone = ProductSerial(id: newId(), tenantId: shop.tenantId, productId: p.id, serial: '354000000000009',
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0, deletedAt: t0);
    await c.read(productServiceProvider).create(p, serials: [x, gone], initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(1)),
    ]);
    expect(await repo.watchInStockSerialValues().first, {'354000000000001'}, reason: 'deleted row is not in stock');

    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: x.id, name: p.name, qtyMilli: 1000, price: 2, cost: 1),
    ], method: PaymentMethod.cash));
    expect(await repo.watchInStockSerialValues().first, isEmpty, reason: 'sold → may be received again');

    await adb.delete(adb.outbox).go();
    await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: ['354000000000001']);
    final units = await outbox(adb);
    expect(units.map((u) => u.kind), ['restock']);
    final sent = (rowsOf(units.single)['productSerials'] as List).cast<Map>();
    expect(sent, hasLength(1), reason: 'only the new row');
    expect((sent.single['serial'], sent.single['status']), ('354000000000001', 'inStock'));
    expect(sent.single['id'], isNot(x.id));
    final rows = await (adb.select(adb.productSerials)..where((s) => s.serial.equals('354000000000001'))).get();
    final oldRow = rows.singleWhere((s) => s.id == x.id);
    expect((oldRow.status.name, oldRow.saleLineId), ('sold', sale.lines.single.id), reason: 'history kept');
    expect(await repo.watchInStockSerialValues().first, {'354000000000001'});

    // Record (not asserted, so a BUG-23 fix does not break this test) what voiding the ORIGINAL sale sends — the wire
    // shape used by the server test TC_SYNC_NEW_9. Round 5 observed: one voidSale unit whose productSerials = [the OLD
    // row id, status inStock], and afterwards 2 in-stock rows with the IMEI on the phone.
    await adb.delete(adb.outbox).go();
    try {
      await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    } catch (e) {
      printOnFailure('void refused: $e');
    }
    final v = await outbox(adb);
    final vs = v.isEmpty ? const [] : ((rowsOf(v.single)['productSerials'] as List?)?.cast<Map>() ?? const []);
    final after = (await repo.watchSerials(p.id).first)
        .where((s) => s.serial == '354000000000001' && s.status == SerialStatus.inStock);
    // ignore: avoid_print
    print('TC-PROD-NEW-26 Drift record: units ${v.map((u) => u.kind)}, productSerials '
        '${vs.map((s) => '${s['id'] == x.id ? 'OLD' : 'other'}/${s['status']}')}, in-stock rows after: ${after.length}');
  });
}
