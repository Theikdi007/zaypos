// QA round 1 — money / stock / debt / report rules on the REAL local database
// (in-memory Drift, the app's composition root, no network).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:drift/drift.dart' show Value;
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/data/debt_repository.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/customer_account.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/reports/domain/report_builder.dart';
import 'package:zaypos_app/features/reports/data/report_providers.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';
import '../helpers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late TestShop me;

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> open({bool seed = true}) async {
    db = memoryDb();
    (c, me) = await driftContainer(db, seed: seed);
  }

  Product product({String name = 'QA ပစ္စည်း', int cost = 450, int price = 600}) {
    final t = nowUtc();
    return Product(
      id: newId(), tenantId: me.tenantId, name: name, cost: cost, price: price, category: 'General',
      tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t,
    );
  }

  Future<int> stockOf(String id) async => (await settled(c, productsProvider)).firstWhere((p) => p.id == id).stockMilli;
  Future<int> balanceOf(String customerId) async => (await settled(c, customerAccountProvider(customerId)))!.balance;

  /// Re-reads a stream-backed value until [ok] or a short timeout (Drift streams are async).
  Future<T> until<T>(Future<T> Function() read, bool Function(T) ok) async {
    var v = await read();
    for (var i = 0; i < 100 && !ok(v); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      v = await read();
    }
    return v;
  }

  Future<PeriodSummary> today() async => (await settled(c, reportProvider(ReportPeriod.today))).summary;

  // ---------------------------------------------------------------- TC-POS-01 / TC-POS-09
  test('TC-POS-01 / TC-POS-09 a new shop numbers 2,500 sales A-0001 … A-2500, no gaps or repeats', () async {
    await open(seed: false);
    final p = product();
    await c.read(productServiceProvider).create(p);
    final line = draft(productId: p.id, name: p.name, qtyMilli: 1000, price: 600, cost: 450);

    final nos = <String>[];
    for (var i = 0; i < 2500; i++) {
      nos.add((await sell(c, [line])).no);
    }

    expect(nos.first, 'A-0001');
    expect(nos.last, 'A-2500');
    expect(nos, [for (var i = 1; i <= 2500; i++) 'A-${i.toString().padLeft(4, '0')}']);
    final stored = (await db.select(db.sales).get()).map((s) => s.no).toList();
    expect(stored.toSet(), hasLength(2500), reason: 'no repeats in the database');
    expect((await db.select(db.devices).getSingle()).lastSeq, 2500);
  }, timeout: const Timeout(Duration(minutes: 5)));

  // ---------------------------------------------------------------- TC-POS-10
  test('TC-POS-10 600 Ks × 2.5 = 1,500 Ks (Qty.lineTotal), stored and pushed as 1,500', () async {
    await open(seed: false);
    final p = product(price: 600);
    await c.read(productServiceProvider).create(p);
    expect(Qty.lineTotal(600, 2500), 1500);
    expect(Qty.lineTotal(333, 2500), 833, reason: 'half rounds up, same as the server test (832.5 → 833)');

    final sale = await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 2500, price: 600)]);

    expect(sale.total, 1500);
    final unit = (await outbox(db)).last;
    expect(rowsOf(unit)['sales'].single['total'], 1500);
    expect(rowsOf(unit)['saleLines'].single['lineTotal'], 1500);
  });

  // ---------------------------------------------------------------- TC-SALE-01 / TC-SALE-03
  test('TC-SALE-01 void a cash sale: voided, stock returned, today total reduced', () async {
    await open();
    final before = await today();
    final stock0 = await stockOf(SeedIds.water);
    final sale = await sell(c, [draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: 2000, price: 600, cost: 450)]);
    await until(today, (s) => s.sales == before.sales + 1200);

    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);

    expect((await settled(c, saleByIdProvider(sale.id)))!.voided, isTrue);
    expect(await until(() => stockOf(SeedIds.water), (s) => s == stock0), stock0);
    expect((await until(today, (s) => s.sales == before.sales)).sales, before.sales);
  });

  test('TC-SALE-03 void then un-void: stock and debt back to the pre-void state, exactly once', () async {
    await open();
    final stock0 = await stockOf(SeedIds.water);
    final debt0 = await balanceOf(SeedIds.aungKyaw);
    final sale = await sell(c, [draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: 3000, price: 600, cost: 450)],
        method: PaymentMethod.debt, customerId: SeedIds.aungKyaw);
    final stockSold = await until(() => stockOf(SeedIds.water), (s) => s == stock0 - 3000);
    final debtSold = await until(() => balanceOf(SeedIds.aungKyaw), (b) => b == debt0 + 1800);
    expect((stockSold, debtSold), (stock0 - 3000, debt0 + 1800));

    final svc = c.read(voidSaleServiceProvider);
    await svc.setVoided(sale.id, true);
    await svc.setVoided(sale.id, false);
    await svc.setVoided(sale.id, false); // repeated un-void: no-op

    expect(await until(() => stockOf(SeedIds.water), (s) => s == stockSold), stockSold);
    expect(await until(() => balanceOf(SeedIds.aungKyaw), (b) => b == debtSold), debtSold);
    expect((await settled(c, saleByIdProvider(sale.id)))!.voided, isFalse);
    expect((await outbox(db)).map((u) => u.kind), ['checkout', 'voidSale', 'voidSale']);
  });

  // ---------------------------------------------------------------- TC-RPT-01 / TC-RPT-02
  test('TC-RPT-01 today: voided excluded, debt included, profit = Σ(price − costSnapshot) × qty', () async {
    await open(seed: false);
    final p = product(cost: 450, price: 600);
    await c.read(productServiceProvider).create(p);
    final cust = Customer(id: newId(), tenantId: me.tenantId, name: 'QA', phone: '', createdAt: nowUtc(), updatedAt: nowUtc());
    await c.read(customerServiceProvider).create(cust);

    await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 2000, price: 600, cost: 450)]); // 1,200 / profit 300
    final voided = await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 5000, price: 600, cost: 450)]);
    await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 2500, price: 600, cost: 450)],
        method: PaymentMethod.debt, customerId: cust.id); // 1,500 / profit 375
    await c.read(voidSaleServiceProvider).setVoided(voided.id, true);

    final s = await until(today, (s) => s.count == 2);
    expect((s.count, s.sales, s.profit), (2, 2700, 675));
  });

  test('TC-RPT-02 changing a product cost after selling it does not change past profit', () async {
    await open(seed: false);
    final p = product(cost: 450, price: 600);
    await c.read(productServiceProvider).create(p);
    await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 2000, price: 600, cost: 450)]);
    final before = await until(today, (s) => s.count == 1);

    // New cost (the app has no product-edit screen — see TC-PROD-NEW-1 — so the edit arrives as a
    // newer product row, exactly as a pull from another phone writes it).
    await (db.update(db.products)..where((x) => x.id.equals(p.id)))
        .write(ProductsCompanion(cost: const Value(580), updatedAt: Value(nowUtc())));
    expect((await db.select(db.products).getSingle()).cost, 580);

    final after = await today();
    expect(after.profit, before.profit);
    expect(after.profit, 300);
  });

  // ---------------------------------------------------------------- TC-RPT-03
  test('TC-RPT-03 today / week / month: totals, payment split and top products match the sales list', () async {
    await open(); // sample shop: 500+ sales over several weeks
    final sales = (await settled(c, salesProvider)).where((s) => !s.voided && s.deletedAt == null).toList();
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    for (final period in ReportPeriod.values) {
      final from = switch (period) {
        ReportPeriod.today => today0,
        ReportPeriod.week => today0.subtract(const Duration(days: 6)),
        ReportPeriod.month => DateTime(now.year, now.month, 1),
      };
      final inP = sales.where((s) => !s.createdAt.toLocal().isBefore(from) && s.createdAt.toLocal().isBefore(today0.add(const Duration(days: 1)))).toList();
      final r = await settled(c, reportProvider(period));
      expect((r.summary.count, r.summary.sales, r.summary.profit),
          (inP.length, inP.fold<int>(0, (a, s) => a + s.total), inP.fold<int>(0, (a, s) => a + s.profit)), reason: period.name);
      final byMethod = {for (final m in PaymentMethod.values) m: inP.where((s) => s.method == m).fold<int>(0, (a, s) => a + s.total)};
      final total = byMethod.values.fold<int>(0, (a, b) => a + b);
      expect(r.paymentShares.fold<int>(0, (a, x) => a + x.percent), total == 0 ? 0 : 100, reason: '${period.name} split sums to 100');
      for (final share in r.paymentShares) {
        if (total == 0) continue;
        expect((share.percent - byMethod[share.method]! * 100 / total).abs(), lessThan(1.0), reason: '${period.name} ${share.method.name}');
      }
      final perProduct = <String, int>{};
      for (final l in inP.expand((s) => s.lines)) {
        perProduct[l.productId ?? l.name] = (perProduct[l.productId ?? l.name] ?? 0) + l.total;
      }
      final top = perProduct.values.toList()..sort((a, b) => b.compareTo(a));
      expect(r.topProducts.map((t) => t.amount), top.take(4), reason: '${period.name} top products');
    }
  });

  // ---------------------------------------------------------------- TC-RPT-04
  test('TC-RPT-04 sales just before / after local midnight land on the right local day', () {
    final tz = DateTime.now().timeZoneOffset;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day); // local 00:00 today
    Sale at(DateTime local, int total) => Sale(
          id: newId(), tenantId: 't', no: 'A-${total.toString().padLeft(4, '0')}', method: PaymentMethod.cash,
          lines: [
            SaleLine(id: newId(), tenantId: 't', saleId: 'x', name: 'x', qtyMilli: 1000, price: total, costSnapshot: 0,
                createdAt: local.toUtc(), updatedAt: local.toUtc()),
          ],
          payments: const [],
          createdAt: local.toUtc(), // stored as UTC like the app
          updatedAt: local.toUtc(),
        );
    final sales = [
      at(midnight.subtract(const Duration(seconds: 1)), 1000), // 23:59:59 yesterday
      at(midnight, 2000), // 00:00:00 today
      at(midnight.add(const Duration(hours: 6, minutes: 29)), 4000), // before 06:30 local = still "yesterday" in UTC
    ];
    final r = ReportBuilder.build(sales, const {}, ReportPeriod.today, now: midnight.add(const Duration(hours: 12)));
    expect(r.summary.sales, 6000, reason: 'local day (offset $tz), not the UTC day');
    expect(r.last7Days[5].amount, 1000, reason: 'yesterday');
    expect(r.last7Days[6].amount, 6000, reason: 'today');
  });

  // ---------------------------------------------------------------- TC-DEBT-01..04
  test('TC-DEBT-01..04 opening 52,000 → +24,000 credit sale → −20,000 KBZPay → overpay goes negative', () async {
    await open(seed: false);
    final totalBefore = (await settled(c, customerAccountsProvider)).fold<int>(0, (a, x) => a + (x.balance > 0 ? x.balance : 0));
    final cust = Customer(id: newId(), tenantId: me.tenantId, name: 'ဒေါ်ခင်မာ', phone: '', createdAt: nowUtc(), updatedAt: nowUtc());
    await c.read(customerServiceProvider).create(cust, openingBalance: 52000);
    // Round 2: wait for the Drift streams like every other step. customerAccountsProvider joins three
    // independent streams (customers, ledger, balances); a single settled() read right after the write
    // can return the join of the NEW customers list with the OLD balances map (balance 0) — a test
    // timing defect, not a product one (the stored balance is checked below, straight from SQL).
    expect(await until(() => balanceOf(cust.id), (b) => b == 52000), 52000);
    expect((await c.read(debtRepositoryProvider).watchBalances().first)[cust.id], 52000, reason: 'SQL balance');
    int positiveTotal(List<CustomerAccount> all) => all.fold<int>(0, (a, x) => a + (x.balance > 0 ? x.balance : 0));
    final total = await until(() async => positiveTotal(await settled(c, customerAccountsProvider)),
        (t) => t == totalBefore + 52000);
    expect(total, totalBefore + 52000, reason: 'TC-DEBT-01: total ရရန်ကျန် updated');

    final p = product(price: 24000, cost: 20000);
    await c.read(productServiceProvider).create(p);
    await sell(c, [draft(productId: p.id, name: p.name, qtyMilli: 1000, price: 24000, cost: 20000)],
        method: PaymentMethod.debt, customerId: cust.id);
    expect(await until(() => balanceOf(cust.id), (b) => b == 76000), 76000, reason: 'TC-DEBT-02');
    var history = (await settled(c, customerAccountProvider(cust.id)))!.history;
    expect(history.where((e) => e.type == DebtEntryType.creditSale).single.effect, 24000);

    await c.read(customerServiceProvider)
        .recordPayment(tenantId: me.tenantId, customerId: cust.id, amount: 20000, method: PaymentMethod.kbz);
    expect(await until(() => balanceOf(cust.id), (b) => b == 56000), 56000, reason: 'TC-DEBT-03');
    history = (await settled(c, customerAccountProvider(cust.id)))!.history;
    final pay = history.where((e) => e.type == DebtEntryType.payment).single;
    expect((pay.effect, pay.method), (-20000, PaymentMethod.kbz));

    // TC-DEBT-04 (record behaviour): paying 60,000 on 56,000 is accepted; balance −4,000.
    await c.read(customerServiceProvider)
        .recordPayment(tenantId: me.tenantId, customerId: cust.id, amount: 60000, method: PaymentMethod.cash);
    expect(await until(() => balanceOf(cust.id), (b) => b == -4000), -4000);
  });

  // ---------------------------------------------------------------- TC-DEBT-06
  test('TC-DEBT-06 1,000 ledger entries: balance is a SQL SUM and the customers list loads < 300 ms', () async {
    await open(seed: false);
    final repo = c.read(debtRepositoryProvider);
    final ids = <String>[];
    for (var k = 0; k < 20; k++) {
      final cust = Customer(id: newId(), tenantId: me.tenantId, name: 'C$k', phone: '', createdAt: nowUtc(), updatedAt: nowUtc());
      ids.add(cust.id);
      await c.read(customerServiceProvider).create(cust);
    }
    // 750 credit entries + 250 repayments, written like the services do (inside a unit of work).
    for (var i = 0; i < 1000; i++) {
      final t = nowUtc();
      final pay = i % 4 == 3;
      await c.read(unitOfWorkProvider).run(pay ? UnitKind.payDebt : UnitKind.upsertCustomer, () => repo.add(DebtEntry(
            id: newId(), tenantId: me.tenantId, customerId: ids[i % 20],
            type: pay ? DebtEntryType.payment : DebtEntryType.adjustment, amount: 1000 + i,
            method: pay ? PaymentMethod.cash : null, createdAt: t, updatedAt: t,
          )));
    }
    // The SQL balance equals the ledger effect sum.
    final ledger = await repo.watchAll().first;
    expect(ledger.length, greaterThanOrEqualTo(1000));
    final sums = <String, int>{};
    for (final e in ledger) {
      sums[e.customerId] = (sums[e.customerId] ?? 0) + e.effect;
    }
    expect(await repo.watchBalances().first, sums);

    // Cold read of the customers list (what the Customers screen shows).
    final c2 = ProviderContainer(parent: c);
    addTearDown(c2.dispose);
    final sw = Stopwatch()..start();
    final accounts = await settled(c2, customerAccountsProvider);
    sw.stop();
    expect(accounts, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(300), reason: 'customers list with ${ledger.length} ledger entries');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
