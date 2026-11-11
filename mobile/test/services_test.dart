import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/data/debt_repository.dart';
import 'package:zaypos_app/features/customers/data/fake_customer_repository.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/devices/data/fake_device_repository.dart';
import 'package:zaypos_app/features/inventory/data/fake_stock_repository.dart';
import 'package:zaypos_app/features/products/data/fake_product_repository.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/fake_sales_repository.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

class _FailingDebtRepository implements DebtRepository {
  @override
  Stream<List<DebtEntry>> watchAll() => Stream.value(const []);
  @override
  Future<void> add(DebtEntry entry) async => throw StateError('disk full');
}

void main() {
  final water = draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450);
  Future<int> stockOfWater(ProviderContainer c) async =>
      (await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.water).stockMilli;

  group('CheckoutService validation', () {
    test('credit sale without a customer is rejected and nothing is stored', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final salesBefore = (await val(c, salesProvider)).length;
      await expectLater(
        sell(c, [water], method: PaymentMethod.debt),
        throwsA(isA<CheckoutException>().having((e) => e.error, 'error', CheckoutError.customerRequired)),
      );
      await expectLater(
        sell(c, [water], method: PaymentMethod.debt, customerId: 'no-such-customer'),
        throwsA(isA<CheckoutException>().having((e) => e.error, 'error', CheckoutError.customerRequired)),
      );
      expect((await val(c, salesProvider)).length, salesBefore);
      expect(await stockOfWater(c), Qty.units(48));
    });

    test('cash below total and empty cart are rejected', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      await expectLater(sell(c, [water], received: 1000),
          throwsA(isA<CheckoutException>().having((e) => e.error, 'error', CheckoutError.insufficientCash)));
      await expectLater(sell(c, const []),
          throwsA(isA<CheckoutException>().having((e) => e.error, 'error', CheckoutError.emptyCart)));
      final ok = await sell(c, [water], received: 1200);
      expect(ok.change, 0);
    });
  });

  group('VoidSaleService', () {
    test('void restores stock and reverses debt; un-void re-applies both', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      Future<int> balance() async => (await val(c, customerAccountProvider(SeedIds.aungKyaw)))!.balance;
      expect(await balance(), 52000);

      final sale = await sell(c, [water], method: PaymentMethod.debt, customerId: SeedIds.aungKyaw);
      expect(await stockOfWater(c), Qty.units(46));
      expect(await balance(), 53200);

      final svc = c.read(voidSaleServiceProvider);
      await svc.setVoided(sale.id, true);
      expect((await val(c, saleByIdProvider(sale.id)))!.voided, isTrue);
      expect(await stockOfWater(c), Qty.units(48));
      expect(await balance(), 52000);
      // Ledger is append-only: the credit sale is still there, reversed by an adjustment.
      final forSale = (await val(c, debtLedgerProvider)).where((e) => e.saleId == sale.id).toList();
      expect(forSale.map((e) => e.type).toSet(), {DebtEntryType.creditSale, DebtEntryType.adjustment});

      await svc.setVoided(sale.id, true); // idempotent
      expect(await stockOfWater(c), Qty.units(48));

      await svc.setVoided(sale.id, false);
      expect(await stockOfWater(c), Qty.units(46));
      expect(await balance(), 53200);
    });

    test('voiding the seeded credit sale A-1030 returns its stock', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final ricesBefore = (await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.rice).stockMilli;
      await c.read(voidSaleServiceProvider).setVoided(SeedIds.sale1030, true);
      expect((await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.rice).stockMilli, ricesBefore + Qty.units(2));
      expect((await val(c, customerAccountProvider(SeedIds.aungKyaw)))!.balance, 28000);
    });
  });

  group('unit of work', () {
    test('a failure part-way through checkout rolls back every write', () async {
      final db = seedFakeDatabase('t');
      final salesBefore = db.sales.length, stockBefore = db.stock.length, seqBefore = db.devices.single.lastSeq;
      final svc = CheckoutService(
        uow: FakeUnitOfWork(db),
        tenantId: 't',
        sales: FakeSalesRepository(db),
        stock: FakeStockRepository(db),
        debt: _FailingDebtRepository(),
        customers: FakeCustomerRepository(db),
        devices: FakeDeviceRepository(db, deviceId: db.devices.single.id),
        products: FakeProductRepository(db),
      );
      await expectLater(
        svc.checkout(CheckoutRequest(lines: [water], method: PaymentMethod.debt, customerId: SeedIds.aungKyaw)),
        throwsStateError,
      );
      expect(db.sales.length, salesBefore);
      expect(db.stock.length, stockBefore);
      expect(db.devices.single.lastSeq, seqBefore); // receipt number not consumed
    });

    test('nested transactions join the outer one', () async {
      final db = FakeDatabase();
      await expectLater(
        db.transaction(() async {
          db.sales.addAll(seedSales('t').take(1));
          await db.transaction(() async => db.stock.addAll(seedStock('t').take(1)));
          throw StateError('outer fails');
        }),
        throwsStateError,
      );
      expect(db.sales, isEmpty);
      expect(db.stock, isEmpty);
    });
  });

  test('selling a serial marks it sold; voiding puts it back in stock', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final repo = c.read(productRepositoryProvider);
    final t = nowUtc();
    final serial = ProductSerial(
      id: newId(),
      tenantId: 't',
      productId: SeedIds.water,
      serial: '356984102231457',
      status: SerialStatus.inStock,
      createdAt: t,
      updatedAt: t,
    );
    await repo.add((await repo.watchAll().first).first.copyWith(), serials: [serial]);
    final line = (
      productId: SeedIds.water,
      variantId: null,
      batchId: null,
      serialId: serial.id,
      name: 'phone',
      qtyMilli: 1000,
      price: 100,
      cost: 50,
    );
    final sale = await sell(c, [line]);
    Future<ProductSerial> current() async =>
        (await repo.watchSerials(SeedIds.water).first).firstWhere((s) => s.id == serial.id);
    expect((await current()).status, SerialStatus.sold);
    expect((await current()).saleLineId, sale.lines.single.id);
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    expect((await current()).status, SerialStatus.inStock);
    expect((await current()).saleLineId, isNull);
  });
}
