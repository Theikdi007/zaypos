// Code-review acceptance tests — one group per requirement (step 8).
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/data/fake_customer_repository.dart';
import 'package:zaypos_app/features/customers/data/fake_debt_repository.dart';
import 'package:zaypos_app/features/devices/data/fake_device_repository.dart';
import 'package:zaypos_app/features/inventory/data/fake_stock_repository.dart';
import 'package:zaypos_app/features/inventory/data/stock_providers.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/data/fake_product_repository.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/reports/data/fake_report_repository.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/fake_sales_repository.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

CheckoutService _checkoutOn(FakeDatabase db, String deviceId) => CheckoutService(
      uow: FakeUnitOfWork(db),
      tenantId: 't',
      sales: FakeSalesRepository(db),
      stock: FakeStockRepository(db),
      debt: FakeDebtRepository(db),
      customers: FakeCustomerRepository(db),
      devices: FakeDeviceRepository(db, deviceId: deviceId),
      products: FakeProductRepository(db),
    );

void main() {
  final water = draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450);

  group('1. debt without customer is rejected', () {
    test('no customer / unknown customer -> CheckoutError.customerRequired, nothing written', () async {
      final db = seedFakeDatabase('t');
      final svc = _checkoutOn(db, db.devices.single.id);
      final before = (db.sales.length, db.stock.length, db.debt.length, db.devices.single.lastSeq);
      for (final customerId in [null, 'ghost']) {
        await expectLater(
          svc.checkout(CheckoutRequest(lines: [water], method: PaymentMethod.debt, customerId: customerId)),
          throwsA(isA<CheckoutException>().having((e) => e.error, 'error', CheckoutError.customerRequired)),
        );
      }
      expect((db.sales.length, db.stock.length, db.debt.length, db.devices.single.lastSeq), before);
    });
  });

  group('2. void restores stock + reverses debt', () {
    test('credit sale of a batch-tracked line: void returns stock to the batch and zeroes the debt effect', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final line = (
        productId: SeedIds.water,
        variantId: null,
        batchId: 'batch-1',
        serialId: null,
        name: 'ရေသန့် 1L',
        qtyMilli: Qty.units(3),
        price: 600,
        cost: 450,
      );
      final balance0 = (await val(c, customerAccountProvider(SeedIds.aungKyaw)))!.balance;
      final stock0 = (await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.water).stockMilli;

      final sale = await sell(c, [line], method: PaymentMethod.debt, customerId: SeedIds.aungKyaw);
      await c.read(voidSaleServiceProvider).setVoided(sale.id, true);

      final moves = (await val(c, stockMovementsProvider)).where((m) => m.saleId == sale.id).toList();
      expect(moves.map((m) => (m.type, m.qtyMilli, m.batchId)), [
        (StockMovementType.sale, -Qty.units(3), 'batch-1'),
        (StockMovementType.voidReturn, Qty.units(3), 'batch-1'),
      ]);
      expect((await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.water).stockMilli, stock0);
      expect((await val(c, customerAccountProvider(SeedIds.aungKyaw)))!.balance, balance0);
    });
  });

  group('3. profit uses costSnapshot', () {
    test('changing the product cost after the sale does not change recorded profit', () async {
      final db = seedFakeDatabase('t');
      final report = FakeReportRepository(db);
      final before = report.report(ReportPeriod.today).summary.profit;
      await _checkoutOn(db, db.devices.single.id).checkout(CheckoutRequest(lines: [water], method: PaymentMethod.cash));
      final afterSale = report.report(ReportPeriod.today).summary.profit;
      expect(afterSale - before, 2 * (600 - 450));

      // Supplier raises the price: cost 450 -> 590 on the product master.
      final i = db.products.indexWhere((p) => p.id == SeedIds.water);
      db.products[i] = db.products[i].copyWith(cost: 590);
      expect(report.report(ReportPeriod.today).summary.profit, afterSale);
    });
  });

  group('4. receipt numbers unique per device', () {
    test('two devices selling interleaved against one database never collide', () async {
      final db = seedFakeDatabase('t');
      db.devices.add(seedDevice('t', code: 'B', lastSeq: 1032)); // same seq as A on purpose
      final a = _checkoutOn(db, db.devices[0].id);
      final b = _checkoutOn(db, db.devices[1].id);
      final nos = <String>[];
      for (var i = 0; i < 10; i++) {
        nos.add((await a.checkout(CheckoutRequest(lines: [water], method: PaymentMethod.cash))).no);
        nos.add((await b.checkout(CheckoutRequest(lines: [water], method: PaymentMethod.kbz))).no);
      }
      expect(nos.toSet(), hasLength(20));
      expect(nos.take(4), ['A-1033', 'B-1033', 'A-1034', 'B-1034']);
      expect(db.sales.map((s) => s.no).toSet(), hasLength(db.sales.length));
    });
  });

  group('5. stock = sum of movements', () {
    test('after mixed activity, every product view equals the sum of its movements', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final s1 = await sell(c, [water]);
      await sell(c, [draft(productId: SeedIds.rice, qtyMilli: Qty.units(1), price: 7400, cost: 6800), water]);
      final voidSvc = c.read(voidSaleServiceProvider);
      await voidSvc.setVoided(s1.id, true);
      await voidSvc.setVoided(s1.id, false);
      await voidSvc.setVoided(SeedIds.sale1030, true);

      final moves = await val(c, stockMovementsProvider);
      final views = await val(c, productsProvider);
      for (final v in views) {
        expect(v.stockMilli, stockOf(moves.where((m) => m.productId == v.id)), reason: v.name);
      }
      // Water: 48 opening − 2 − 2 (s1 sold, voided, re-sold nets −2) − 2 (second sale) + 2 (A-1030 void)
      expect(views.firstWhere((v) => v.id == SeedIds.water).stockMilli, Qty.units(48 - 2 - 2 + 2));
    });
  });
}
