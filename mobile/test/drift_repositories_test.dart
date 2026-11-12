import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/app/local_bootstrap.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/devices/data/device_providers.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/reports/data/report_providers.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'drift_helpers.dart';
import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late LocalIdentity me;

  setUp(() async {
    db = memoryDb();
    (c, me) = await driftContainer(db);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  final water = draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450);
  Future<int> stockOf(String id) async => (await settled(c, productsProvider)).firstWhere((p) => p.id == id).stockMilli;

  test('bootstrap: seeded sample shop, no outbox, idempotent identity', () async {
    expect(await outbox(db), isEmpty, reason: 'local bootstrap is not user data');
    expect((await settled(c, salesProvider)).length, greaterThan(500));
    expect((await settled(c, deviceProvider)).nextReceiptNo, 'A-1033');
    expect(await stockOf(SeedIds.water), Qty.units(48));
    final again = await bootstrapLocalDatabase(db, seedSampleData: true);
    expect((again.tenantId, again.deviceId), (me.tenantId, me.deviceId));
    expect(await db.select(db.products).get(), hasLength(SeedCatalog.items.length), reason: 'seeded once');
  });

  test('checkout = one checkout unit with sale, lines, payment, movements and device lastSeq', () async {
    final sale = await sell(c, [water], received: 2000);

    expect(sale.no, 'A-1033');
    expect(await stockOf(SeedIds.water), Qty.units(46));
    expect((await settled(c, saleByIdProvider(sale.id)))!.change, 800);
    final u = (await outbox(db)).single;
    expect(u.kind, 'checkout');
    final rows = rowsOf(u);
    expect(rows.keys.toSet(), {'devices', 'sales', 'saleLines', 'payments', 'stockMovements'});
    expect(rows['devices'].single, allOf(containsPair('id', me.deviceId), containsPair('lastSeq', 1033)));
    expect(rows['sales'].single, allOf(
      containsPair('no', 'A-1033'),
      containsPair('method', 'cash'),
      containsPair('total', 1200),
      containsPair('tenantId', me.tenantId),
      containsPair('deviceId', me.deviceId),
    ));
    expect((rows['sales'].single as Map).containsKey('syncedAt'), isFalse, reason: 'server output only');
    expect(rows['saleLines'].single, allOf(containsPair('lineTotal', 1200), containsPair('qtyMilli', 2000)));
    expect(rows['payments'].single, allOf(containsPair('amount', 1200), containsPair('received', 2000)));
    expect(rows['stockMovements'].single, allOf(containsPair('type', 'sale'), containsPair('qtyMilli', -2000)));
  });

  test('credit checkout records the debt entry in the same unit; void is its own voidSale unit', () async {
    Future<int> balance() async => (await settled(c, customerAccountProvider(SeedIds.aungKyaw)))!.balance;
    expect(await balance(), 52000);

    final sale = await sell(c, [water], method: PaymentMethod.debt, customerId: SeedIds.aungKyaw);
    expect(await balance(), 53200);
    expect(rowsOf((await outbox(db)).single)['debtEntries'].single, containsPair('type', 'creditSale'));

    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    expect((await settled(c, saleByIdProvider(sale.id)))!.voided, isTrue);
    expect(await stockOf(SeedIds.water), Qty.units(48));
    expect(await balance(), 52000);

    final units = await outbox(db);
    expect(units.map((u) => u.kind), ['checkout', 'voidSale']);
    final v = rowsOf(units.last);
    expect(v['sales'].single['voidedAt'], isNotNull);
    expect(v['stockMovements'].single, allOf(containsPair('type', 'voidReturn'), containsPair('qtyMilli', 2000)));
    expect(v['debtEntries'].single, allOf(containsPair('type', 'adjustment'), containsPair('amount', -1200)));

    await c.read(voidSaleServiceProvider).setVoided(sale.id, true); // no-op
    expect(await outbox(db), hasLength(2));
  });

  test('a failing checkout leaves no sale, no movement, no receipt number and no outbox row', () async {
    final salesBefore = (await db.select(db.sales).get()).length;
    await expectLater(sell(c, [water], received: 100), throwsA(isA<Exception>()));
    expect(await db.select(db.sales).get(), hasLength(salesBefore));
    expect((await settled(c, deviceProvider)).lastSeq, 1032);
    expect(await outbox(db), isEmpty);
  });

  test('product with batches and serials: one upsertProduct unit; batch qty is derived from movements', () async {
    final t = nowUtc();
    final p = Product(
      id: newId(),
      tenantId: me.tenantId,
      name: 'Paracetamol',
      cost: 100,
      price: 150,
      category: 'ဆေး',
      tint: 0xFFE0F2F1,
      initial: 'P',
      createdAt: t,
      updatedAt: t,
    );
    final batch = ProductBatch(
      id: newId(),
      tenantId: me.tenantId,
      productId: p.id,
      batchNo: 'LOT-7',
      expiryDate: DateTime.utc(2027, 3, 31),
      qtyMilli: 0,
      createdAt: t,
      updatedAt: t,
    );
    final serial = ProductSerial(
      id: newId(),
      tenantId: me.tenantId,
      productId: p.id,
      serial: '356938035643809',
      status: SerialStatus.inStock,
      createdAt: t,
      updatedAt: t,
    );
    await c.read(productServiceProvider).create(p, batches: [batch], serials: [serial], initialStock: [
      restockMovement(tenantId: me.tenantId, productId: p.id, qtyMilli: Qty.units(40), batchId: batch.id),
    ]);

    final repo = c.read(productRepositoryProvider);
    expect((await repo.watchBatches(p.id).first).single.qtyMilli, Qty.units(40));
    await sell(c, [(productId: p.id, variantId: null, batchId: batch.id, serialId: serial.id, name: 'x', qtyMilli: 3000, price: 150, cost: 100)]);
    expect((await repo.watchBatches(p.id).first).single.qtyMilli, Qty.units(37));
    expect((await repo.watchSerials(p.id).first).single.status, SerialStatus.sold);

    final units = await outbox(db);
    expect(units.map((u) => u.kind), ['upsertProduct', 'checkout']);
    final up = rowsOf(units.first);
    expect(up.keys.toSet(), {'products', 'productBatches', 'productSerials', 'stockMovements'});
    expect(up['productBatches'].single, allOf(containsPair('expiryDate', '2027-03-31'), isNot(contains('qtyMilli'))));
    expect(rowsOf(units.last)['productSerials'].single, allOf(containsPair('status', 'sold'), containsPair('saleLineId', isNotNull)));
  });

  test('customer + opening balance = upsertCustomer; repayment = payDebt; restock/adjust have their kinds', () async {
    final t = nowUtc();
    final svc = c.read(customerServiceProvider);
    final customerId = newId();
    await svc.create(
      Customer(id: customerId, tenantId: me.tenantId, name: 'မမြ', phone: '09', createdAt: t, updatedAt: t),
      openingBalance: 9000,
    );
    await svc.recordPayment(tenantId: me.tenantId, customerId: customerId, amount: 4000, method: PaymentMethod.kbz);
    await c.read(stockServiceProvider).restock(productId: SeedIds.coffee, qtyMilli: Qty.units(12));
    await c.read(stockServiceProvider).adjust(productId: SeedIds.coffee, deltaMilli: -Qty.units(2));

    expect((await outbox(db)).map((u) => u.kind), ['upsertCustomer', 'payDebt', 'restock', 'stockAdjust']);
    expect((await settled(c, customerAccountProvider(customerId)))!.balance, 5000);
    expect(await stockOf(SeedIds.coffee), Qty.units(10));
  });

  test('feature toggles are stored and pushed as setFeatures; a new container reads them back', () async {
    c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.serialWarranty, true);
    await pumpEventQueue();
    for (var i = 0; i < 50 && (await outbox(db)).isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final u = (await outbox(db)).single;
    expect(u.kind, 'setFeatures');
    expect(rowsOf(u)['tenantFeatures'].single, allOf(
      containsPair('featureKey', 'serialWarranty'),
      containsPair('enabled', true),
      containsPair('tenantId', me.tenantId),
    ));

    final (c2, _) = await driftContainer(db);
    addTearDown(c2.dispose);
    c2.read(tenantFeaturesProvider); // start listening
    for (var i = 0; i < 100 && !c2.read(tenantFeaturesProvider).serialWarranty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(c2.read(tenantFeaturesProvider).serialWarranty, isTrue);
  });

  test('reports read the Drift sales (voided excluded)', () async {
    final before = (await settled(c, reportProvider(ReportPeriod.today))).summary;
    final sale = await sell(c, [water]);
    var after = (await settled(c, reportProvider(ReportPeriod.today))).summary;
    for (var i = 0; i < 50 && after.count == before.count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      after = (await settled(c, reportProvider(ReportPeriod.today))).summary;
    }
    expect(after.count, before.count + 1);
    expect(after.sales, before.sales + 1200);
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    var voided = after;
    for (var i = 0; i < 50 && voided.count == after.count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      voided = (await settled(c, reportProvider(ReportPeriod.today))).summary;
    }
    expect(voided.count, before.count);
  });

  test('the stock read model is a SUM over the ledger', () async {
    final ledger = (await db.select(db.stockMovements).get()).where((m) => m.productId == SeedIds.water);
    expect(await stockOf(SeedIds.water), ledger.fold<int>(0, (a, m) => a + m.qtyMilli));
    expect(await stockOf(SeedIds.coffee), 0, reason: 'no movements');
  });

  test('StockMovementType names match the server enum', () {
    expect(StockMovementType.values.map((e) => e.name), ['sale', 'restock', 'adjustment', 'voidReturn']);
  });
}
