// QA round 5 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round5_test.dart
// Owner decision 3 end to end (TC-SYNC-NEW-10): A sells IMEI X; B (synced) takes X back as a trade-in ("Stock ဖြည့်မယ်" =
// StockService.receive); A sells the traded-in phone again. Expected: every unit accepted (outboxes empty), no sync issue,
// both phones end with 2 rows for X (old: sold with sale 1's line; new: sold with sale 2's line), stock 0.
// Plus decisions 1/2 on the wire: a default (no-expiry) product and a tracked one with batch + expiry reach B unchanged.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live: sold IMEI taken back on B (trade-in) and sold again on A → no issue, history kept on both phones; '
      'no-expiry and batch+expiry products reach B', () async {
    final dbs = <AppDatabase>[];
    final containers = <ProviderContainer>[];
    addTearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      for (final d in dbs) {
        await d.close();
      }
    });

    Future<ProviderContainer> phoneApp() async {
      final db = memoryDb();
      dbs.add(db);
      final store = MemorySecureStore();
      final boot = await bootstrap(db, store);
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, boot, store),
        apiBaseUrlProvider.overrideWithValue(base!),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ]);
      containers.add(c);
      return c;
    }

    AppDatabase dbOf(ProviderContainer c) => dbs[containers.indexOf(c)];

    Future<void> sync(ProviderContainer c) async {
      final e = c.read(syncEngineProvider);
      await e.syncNow(manual: true);
      expect(e.snapshot.lastError, isNull, reason: 'sync failed: ${e.snapshot.lastError}');
      final left = await dbOf(c).select(dbOf(c).outbox).get();
      expect(left.map((o) => '${o.kind}: ${o.status.name} ${o.rejectReason ?? ''}'), isEmpty,
          reason: 'every unit must be accepted by the real server (an outbox must never block)');
    }

    Future<int> stockOf(ProviderContainer c, String productId) async {
      final rows = await (dbOf(c).select(dbOf(c).stockMovements)
            ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull()))
          .get();
      return rows.fold<int>(0, (a, m) => a + m.qtyMilli);
    }

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r5', templateId: 'phone', pin: '135790');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();
    const x = '356000000000001';
    final ph = Product(id: newId(), tenantId: tid, name: 'QA trade-in live r5', cost: 400000, price: 450000, category: 'ဖုန်း',
        tint: 0xFFDBEAFE, initial: 'T', createdAt: t, updatedAt: t);
    final oldRow = ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: x, status: SerialStatus.inStock,
        createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(ph, serials: [oldRow],
        initialStock: [restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(1), note: 'initial')]);
    // decisions 1/2 data: a default (no expiry) product and a tracked one with batch + expiry
    final soap = Product(id: newId(), tenantId: tid, name: 'QA soap live r5', cost: 100, price: 150, category: 'x',
        tint: 0xFFDBEAFE, initial: 'S', createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(soap,
        initialStock: [restockMovement(tenantId: tid, productId: soap.id, qtyMilli: Qty.units(12), note: 'initial')]);
    final med = Product(id: newId(), tenantId: tid, name: 'QA med live r5', cost: 100, price: 150, category: 'x',
        tint: 0xFFDBEAFE, initial: 'M', createdAt: t, updatedAt: t, expiryAlertDays: 30);
    final r5b1 = ProductBatch(id: newId(), tenantId: tid, productId: med.id, batchNo: 'R5B1', qtyMilli: Qty.units(10),
        expiryDate: DateTime.utc(2027, 11, 28), createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(med, batches: [r5b1], initialStock: [
      restockMovement(tenantId: tid, productId: med.id, qtyMilli: Qty.units(10), batchId: r5b1.id, note: 'initial'),
    ]);

    final sale1 = await a.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: ph.id, variantId: null, batchId: null, serialId: oldRow.id, name: ph.name, qtyMilli: 1000, price: 450000, cost: 400000),
    ], method: PaymentMethod.cash));
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    expect(await b.read(productRepositoryProvider).watchInStockSerialValues().first, isNot(contains(x)),
        reason: 'B sees X sold, so B may take it back');

    // B: trade-in
    await b.read(stockServiceProvider).receive(productId: ph.id, qtyMilli: Qty.units(1), serials: [x]);
    await sync(b);
    await sync(a);
    final newRow = (await a.read(productRepositoryProvider).watchSerials(ph.id).first)
        .singleWhere((s) => s.serial == x && s.id != oldRow.id);
    expect(newRow.status, SerialStatus.inStock, reason: 'A pulled B\'s trade-in row');

    // A sells the traded-in phone
    final sale2 = await a.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: ph.id, variantId: null, batchId: null, serialId: newRow.id, name: ph.name, qtyMilli: 1000, price: 450000, cost: 400000),
    ], method: PaymentMethod.cash));
    await sync(a);
    await sync(b);

    for (final (name, c) in [('A', a), ('B', b)]) {
      final issues = await dbOf(c).select(dbOf(c).syncIssues).get();
      expect(issues.map((i) => i.kind), isEmpty, reason: 'phone $name: no sync issue for a trade-in');
      final rows = {for (final s in await c.read(productRepositoryProvider).watchSerials(ph.id).first) s.id: s};
      expect(rows.keys.toSet(), {oldRow.id, newRow.id}, reason: 'phone $name: two rows for X');
      expect((rows[oldRow.id]!.status, rows[oldRow.id]!.saleLineId), (SerialStatus.sold, sale1.lines.single.id),
          reason: 'phone $name: history kept');
      expect((rows[newRow.id]!.status, rows[newRow.id]!.saleLineId), (SerialStatus.sold, sale2.lines.single.id));
      expect(await stockOf(c, ph.id), 0, reason: 'phone $name');
    }

    // decisions 1/2 on B
    final soapB = (await dbOf(b).select(dbOf(b).products).get()).singleWhere((p) => p.id == soap.id);
    expect(soapB.expiryAlertDays, isNull);
    expect(await stockOf(b, soap.id), Qty.units(12));
    final medB = (await dbOf(b).select(dbOf(b).products).get()).singleWhere((p) => p.id == med.id);
    expect(medB.expiryAlertDays, 30);
    final bB = await b.read(productRepositoryProvider).watchBatches(med.id).first;
    expect(bB.map((x) => (x.batchNo, x.qtyMilli, x.expiryDate)), [('R5B1', Qty.units(10), DateTime.utc(2027, 11, 28))]);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
