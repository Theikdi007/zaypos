// QA round 6 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round6_test.dart
// BUG-22 (TC-PROD-NEW-27 / TC-SYNC-NEW-11): A switches a plain product with 10 in stock to expiry tracking with an opening
//   batch — the edit form's unit (shape proven by m/qa/qa_round6_drift_test.dart: ProductService.update with the opening
//   batch + the two "opening batch" adjustments) — B pulls: expiryAlertDays 30, batch with its expiry, batch stock 10,
//   0 outside batches, no issue.
// BUG-23 (TC-PROD-NEW-28 / TC-SYNC-NEW-12): A sells IMEI X; B takes X back (trade-in); A (synced) voids sale 1 → no issue,
//   one in-stock row and stock 1 on both phones, old row sold (history). Then the other order: A sells Y, syncs; A voids
//   the sale OFFLINE while B takes Y back; A pushes first, B second → duplicateSerial on both phones.
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
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live: opening batch from the edit form reaches B; void after a trade-in keeps one in-stock IMEI on both phones; '
      'void and trade-in crossing offline → duplicateSerial on both', () async {
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

    Future<int> stockOf(ProviderContainer c, String productId, {bool Function(String? batchId)? where}) async {
      final rows = await (dbOf(c).select(dbOf(c).stockMovements)
            ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull()))
          .get();
      return rows.where((m) => where == null || where(m.batchId)).fold<int>(0, (a, m) => a + m.qtyMilli);
    }

    Future<List<String>> issues(ProviderContainer c) async =>
        (await dbOf(c).select(dbOf(c).syncIssues).get()).map((i) => i.kind.toString()).toList();

    Future<int> inStock(ProviderContainer c, String productId, String imei) async =>
        (await c.read(productRepositoryProvider).watchSerials(productId).first)
            .where((s) => s.serial == imei && s.status == SerialStatus.inStock && s.deletedAt == null)
            .length;

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r6', templateId: 'phone', pin: '135790');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();

    // ---- BUG-22: plain product with 10, then switched to tracked with an opening batch
    final med = Product(id: newId(), tenantId: tid, name: 'QA med live r6', cost: 100, price: 150, category: 'x',
        tint: 0xFFDBEAFE, initial: 'M', createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(med,
        initialStock: [restockMovement(tenantId: tid, productId: med.id, qtyMilli: Qty.units(10), note: 'initial')]);

    // ---- BUG-23 data: phones X and Y, both sold on A
    const x = '359100000000001', y = '359100000000002';
    final ph = Product(id: newId(), tenantId: tid, name: 'QA phone live r6', cost: 400000, price: 450000, category: 'ဖုန်း',
        tint: 0xFFDBEAFE, initial: 'P', createdAt: t, updatedAt: t);
    final rowX = ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: x, status: SerialStatus.inStock,
        createdAt: t, updatedAt: t);
    final rowY = ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: y, status: SerialStatus.inStock,
        createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(ph, serials: [rowX, rowY],
        initialStock: [restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(2), note: 'initial')]);
    Future<Sale> sellOn(ProviderContainer c, String serialId) => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: ph.id, variantId: null, batchId: null, serialId: serialId, name: ph.name, qtyMilli: 1000, price: 450000,
              cost: 400000),
        ], method: PaymentMethod.cash));
    final saleX = await sellOn(a, rowX.id);
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);

    // A: the edit form's opening-batch unit
    final t2 = nowUtc();
    final open = ProductBatch(id: newId(), tenantId: tid, productId: med.id, batchNo: 'OPENL6', qtyMilli: Qty.units(10),
        expiryDate: DateTime.utc(2027, 11, 28), createdAt: t2, updatedAt: t2);
    await a.read(productServiceProvider).update(
      med.copyWith(expiryAlertDays: () => 30, updatedAt: t2),
      batches: [open],
      movements: [
        for (final (q, bid) in [(-Qty.units(10), null), (Qty.units(10), open.id)])
          StockMovement(id: newId(), tenantId: tid, productId: med.id, batchId: bid, type: StockMovementType.adjustment,
              qtyMilli: q, note: 'opening batch', createdAt: t2, updatedAt: t2),
      ],
    );
    await sync(a);
    await sync(b);
    final medB = (await dbOf(b).select(dbOf(b).products).get()).singleWhere((p) => p.id == med.id);
    expect(medB.expiryAlertDays, 30);
    expect((await b.read(productRepositoryProvider).watchBatches(med.id).first).map((x) => (x.batchNo, x.expiryDate)),
        [('OPENL6', DateTime.utc(2027, 11, 28))]);
    expect((await stockOf(b, med.id, where: (bid) => bid == open.id), await stockOf(b, med.id, where: (bid) => bid == null),
            await stockOf(b, med.id)),
        (Qty.units(10), 0, Qty.units(10)), reason: 'B: batch stock = product stock, nothing loose');

    // ---- BUG-23 (a): B takes X back; A pulls it, then voids sale X
    await b.read(stockServiceProvider).receive(productId: ph.id, qtyMilli: Qty.units(1), serials: [x]);
    await sync(b);
    await sync(a);
    await a.read(voidSaleServiceProvider).setVoided(saleX.id, true);
    await sync(a);
    await sync(b);
    for (final (name, c) in [('A', a), ('B', b)]) {
      expect(await issues(c), isEmpty, reason: 'phone $name: the fixed void raises nothing');
      expect(await inStock(c, ph.id, x), 1, reason: 'phone $name: X in stock once');
      final old = (await c.read(productRepositoryProvider).watchSerials(ph.id).first).singleWhere((s) => s.id == rowX.id);
      expect((old.status, old.saleLineId), (SerialStatus.sold, saleX.lines.single.id), reason: 'phone $name: history');
      expect(await stockOf(c, ph.id), Qty.units(2), reason: 'phone $name: Y (1) + X back once (1)');
    }

    // ---- BUG-23 (b): A sells Y and syncs; then A voids it OFFLINE while B takes Y back; A pushes first
    final saleY = await sellOn(a, rowY.id);
    await sync(a);
    await sync(b);
    await a.read(voidSaleServiceProvider).setVoided(saleY.id, true); // A does not know about B's trade-in yet
    await b.read(stockServiceProvider).receive(productId: ph.id, qtyMilli: Qty.units(1), serials: [y]);
    await sync(a);
    await sync(b);
    await sync(a);
    for (final (name, c) in [('A', a), ('B', b)]) {
      expect(await issues(c), contains(contains('duplicateSerial')),
          reason: 'phone $name: Y in stock twice must reach "စစ်ရန်"');
      expect(await inStock(c, ph.id, y), 2, reason: 'phone $name: both rows kept (README §3.4)');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
