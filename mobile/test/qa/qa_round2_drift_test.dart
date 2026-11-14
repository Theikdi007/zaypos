// QA round 2 — data rules of the BUG-2 / BUG-4 / BUG-5 fixes on the REAL local database
// (in-memory Drift, the app's composition root) and the sync engine with a fake server.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/data/debt_repository.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';

/// Answers every request with [body] (JSON).
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);
  final Map<String, Object?> body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
  @override
  void close({bool force = false}) {}
}

void main() {
  Product product(String tenantId, String name, {DateTime? at, int price = 1000}) {
    final t = at ?? nowUtc();
    return Product(
      id: newId(), tenantId: tenantId, name: name, cost: 100, price: price, category: 'General',
      tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t,
    );
  }

  SaleLineDraft line(Product p, {String? variantId, String? batchId, String? serialId, int qty = 1000}) => (
        productId: p.id, variantId: variantId, batchId: batchId, serialId: serialId,
        name: p.name, qtyMilli: qty, price: p.price, cost: p.cost,
      );

  // ---------------------------------------------------------------- TC-POS-NEW-4 (data half)
  test('TC-POS-NEW-4 Drift: a sale of an IMEI / variant / batch marks THAT one; void gives it back; the unit carries it',
      () async {
    final db = memoryDb();
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final t = nowUtc();
    final tid = shop.tenantId;
    final phone = product(tid, 'QA Galaxy');
    final imeiA = ProductSerial(id: newId(), tenantId: tid, productId: phone.id, serial: '356984102231457',
        status: SerialStatus.inStock, createdAt: t, updatedAt: t);
    final imeiB = ProductSerial(id: newId(), tenantId: tid, productId: phone.id, serial: '356984102231465',
        status: SerialStatus.inStock, createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(phone, serials: [imeiA, imeiB], initialStock: [
      restockMovement(tenantId: tid, productId: phone.id, qtyMilli: Qty.units(2), note: 'initial'),
    ]);
    final shirt = product(tid, 'QA ရှပ်');
    final m = ProductVariant(id: newId(), tenantId: tid, productId: shirt.id, size: 'M', color: 'အနက်', createdAt: t, updatedAt: t);
    final l = ProductVariant(id: newId(), tenantId: tid, productId: shirt.id, size: 'L', color: 'အဖြူ', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(shirt, variants: [m, l], initialStock: [
      restockMovement(tenantId: tid, productId: shirt.id, variantId: m.id, qtyMilli: Qty.units(3), note: 'initial'),
      restockMovement(tenantId: tid, productId: shirt.id, variantId: l.id, qtyMilli: Qty.units(2), note: 'initial'),
    ]);
    final drug = product(tid, 'QA Paracetamol', price: 150);
    final b1 = ProductBatch(id: newId(), tenantId: tid, productId: drug.id, batchNo: 'B1', qtyMilli: 0,
        expiryDate: DateTime.utc(2027, 6, 30), createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(drug, batches: [b1], initialStock: [
      restockMovement(tenantId: tid, productId: drug.id, batchId: b1.id, qtyMilli: Qty.units(40), note: 'initial'),
    ]);
    await db.delete(db.outbox).go();

    final sale = await sell(c, [
      line(phone, serialId: imeiB.id),
      line(shirt, variantId: l.id),
      line(drug, batchId: b1.id, qty: Qty.units(10)),
    ]);

    final repo = c.read(productRepositoryProvider);
    Future<Map<String, SerialStatus>> serials() async =>
        {for (final s in await repo.watchSerials(phone.id).first) s.serial: s.status};
    Future<int> variantStock(String id) async =>
        (await db.select(db.stockMovements).get()).where((x) => x.variantId == id && x.deletedAt == null).fold<int>(0, (a, x) => a + x.qtyMilli);
    Future<int> batchStock() async => (await repo.watchBatches(drug.id).first).single.qtyMilli;

    expect(await serials(), {imeiA.serial: SerialStatus.inStock, imeiB.serial: SerialStatus.sold});
    expect((await variantStock(l.id), await variantStock(m.id)), (Qty.units(1), Qty.units(3)));
    expect(await batchStock(), Qty.units(30));
    final soldSerial = (await (db.select(db.productSerials)..where((x) => x.id.equals(imeiB.id))).getSingle());
    final saleLineIds = {for (final x in sale.lines) x.id};
    expect(saleLineIds, contains(soldSerial.saleLineId), reason: 'the IMEI points at its sale line');

    // The checkout unit tells the server the same (serialDoubleSold / batch stock are computed there).
    final unit = (await outbox(db)).single;
    expect(unit.kind, 'checkout');
    final rows = rowsOf(unit);
    final lines = (rows[WireTable.saleLines] as List).cast<Map<String, dynamic>>();
    expect({for (final x in lines) (x['serialId'], x['variantId'], x['batchId'])},
        {(imeiB.id, null, null), (null, l.id, null), (null, null, b1.id)});
    final serialRow = (rows[WireTable.productSerials] as List).cast<Map<String, dynamic>>().single;
    expect((serialRow['id'], serialRow['status']), (imeiB.id, 'sold'));
    final moves = (rows[WireTable.stockMovements] as List).cast<Map<String, dynamic>>();
    expect(moves.where((x) => x['variantId'] == l.id).single['qtyMilli'], -Qty.units(1));
    expect(moves.where((x) => x['batchId'] == b1.id).single['qtyMilli'], -Qty.units(10));

    // TC-SALE-01 for module products: void returns THAT IMEI / variant / batch.
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    expect(await serials(), {imeiA.serial: SerialStatus.inStock, imeiB.serial: SerialStatus.inStock});
    expect(await variantStock(l.id), Qty.units(2));
    expect(await batchStock(), Qty.units(40));
  });

  // ---------------------------------------------------------------- TC-DEBT-NEW-4 (app half)
  test('TC-DEBT-NEW-4 two phones reverse the same payment offline: same reversal id; after sync phone B has ONE reversal',
      () async {
    final custId = newId();
    final payId = newId();
    final payAt = DateTime.utc(2026, 11, 14, 3);

    // Two phones of one shop, each with the customer (opening 52,000) and the wrong 20,000 KBZ payment.
    Future<(AppDatabase, ProviderContainer, TestShop)> phone() async {
      final db = memoryDb();
      final (c, shop) = await driftContainer(db, seed: false);
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      await c.read(customerServiceProvider).create(
          Customer(id: custId, tenantId: shop.tenantId, name: 'ဒေါ်ခင်မာ', phone: '', createdAt: payAt, updatedAt: payAt),
          openingBalance: 52000);
      await c.read(unitOfWorkProvider).run(UnitKind.payDebt, () => c.read(debtRepositoryProvider).add(DebtEntry(
            id: payId, tenantId: shop.tenantId, customerId: custId, type: DebtEntryType.payment, amount: 20000,
            method: PaymentMethod.kbz, createdAt: payAt, updatedAt: payAt)));
      await db.delete(db.outbox).go();
      return (db, c, shop);
    }

    final (dbA, cA, _) = await phone();
    final (dbB, cB, shopB) = await phone();
    DebtEntry pay(ProviderContainer c) =>
        c.read(customerAccountProvider(custId)).requireValue!.history.firstWhere((e) => e.id == payId);
    await settled(cA, customerAccountProvider(custId));
    await settled(cB, customerAccountProvider(custId));

    final revA = await cA.read(customerServiceProvider).reversePayment(pay(cA));
    await Future<void>.delayed(const Duration(milliseconds: 5)); // B does it a little later (other createdAt)
    final revB = await cB.read(customerServiceProvider).reversePayment(pay(cB));
    expect(revA!.id, revB!.id, reason: 'derived from the payment id on both phones');
    expect(revA.id, paymentReversalId(payId));
    expect((revB.type, revB.amount, revB.customerId), (DebtEntryType.adjustment, 20000, custId));

    for (final db in [dbA, dbB]) {
      final unit = (await outbox(db)).single;
      expect(unit.kind, 'payDebt');
      final row = (rowsOf(unit)[WireTable.debtEntries] as List).single as Map;
      expect((row['id'], row['type'], row['amount']), (revA.id, 'adjustment', 20000));
    }

    // Phone B syncs after A: the server already has A's row with that id (insert-only keeps it, B's unit is
    // applied — see backend QaRound2Tests.TC_DEBT_NEW_4…) and the pull brings A's copy of the same row.
    final storeB = SyncStore(dbB, tenantId: shopB.tenantId, deviceId: shopB.deviceId);
    await storeB.markInitialSyncDone();
    final api = FakeSyncApi()..serverTime = DateTime.now().toUtc();
    final aRow = {
      ...debtWire((await (dbA.select(dbA.debtEntries)..where((x) => x.id.equals(revA.id))).getSingle())),
      'tenantId': shopB.tenantId,
    };
    api.pages.add(page({WireTable.debtEntries: [aRow]}, cursor: '00000000000000D1'));
    await SyncEngine(api: api, store: storeB, deviceId: shopB.deviceId).syncNow(manual: true);

    expect(await outbox(dbB), isEmpty);
    final ledger = await (dbB.select(dbB.debtEntries)..where((x) => x.customerId.equals(custId))).get();
    expect(ledger.where((e) => e.id == revA.id), hasLength(1));
    expect(ledger.where((e) => e.id == payId && e.deletedAt == null), hasLength(1), reason: 'payment never deleted');
    final acct = await until(() => settled(cB, customerAccountProvider(custId)), (a) => a!.balance == 52000);
    expect(acct!.balance, 52000, reason: '52,000 − 20,000 + 20,000 (once)');
    expect((acct.isReversed(pay(cB)), acct.canReverse(pay(cB))), (true, false));
    expect(acct.lastPaymentAt, isNull, reason: 'a reversed payment is not the "last payment"');
  });

  // ---------------------------------------------------------------- TC-SYNC-NEW-2
  test('TC-SYNC-NEW-2 phone clock +1 h: a customer edit is clamped to serverTime + 5 min; a later edit from B is taken',
      () async {
    final db = memoryDb();
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final real = truncateToMs(DateTime.now().toUtc());
    final phoneClock = real.add(const Duration(hours: 1));
    final api = FakeSyncApi()..serverTime = real;
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => phoneClock);

    final cust = Customer(id: newId(), tenantId: shop.tenantId, name: 'A (clock +1h)', phone: '',
        createdAt: phoneClock, updatedAt: phoneClock);
    await c.read(customerServiceProvider).create(cust);
    final p = product(shop.tenantId, 'A product', at: phoneClock);
    await c.read(productServiceProvider).create(p);
    await engine.syncNow(manual: true);

    Future<CustomerRow> custRow() => (db.select(db.customers)..where((x) => x.id.equals(cust.id))).getSingle();
    expect((await custRow()).updatedAt.toUtc(), real.add(SyncStore.maxClockAhead), reason: 'as the server stored it');

    final bAt = real.add(const Duration(minutes: 10));
    api.pages.add(page({
      WireTable.customers: [
        {...customerWire(await custRow()), 'name': 'B (later, correct clock)', 'updatedAt': bAt.toIso8601String()},
      ],
      WireTable.products: [
        {
          ...productWire(await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle()),
          'name': 'B product', 'price': 1100, 'updatedAt': bAt.toIso8601String(),
        },
      ],
    }, cursor: '00000000000000E1'));
    await engine.syncNow(manual: true);

    expect((await custRow()).name, 'B (later, correct clock)');
    final prod = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((prod.name, prod.price), ('B product', 1100));
  });

  test('TC-SYNC-NEW-2 the real push client reads "serverTime" (UTC, …Z) from the answer', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://qa.invalid'))
      ..httpClientAdapter = _JsonAdapter({
        'results': [
          {'unitId': '0192f3a0-0000-7000-8000-000000000001', 'outcome': 'applied', 'issues': <Object>[]},
        ],
        'serverTime': '2026-11-14T03:30:00.123Z',
      });
    final r = await DioSyncApi(dio).push('dev', const []);
    expect(r.results.single.outcome, UnitOutcome.applied);
    expect(r.serverTime, DateTime.utc(2026, 11, 14, 3, 30, 0, 123));
    expect(r.serverTime!.isUtc, isTrue);
  });
}

/// Re-reads [read] until [ok] (Drift streams are async).
Future<T> until<T>(Future<T> Function() read, bool Function(T) ok) async {
  var v = await read();
  for (var i = 0; i < 100 && !ok(v); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    v = await read();
  }
  return v;
}
