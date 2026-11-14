// QA round 4 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round4_test.dart
// BUG-18 end to end (TC-SYNC-NEW-5): phones A and B both receive the SAME IMEI while offline ("Stock ဖြည့်မယ်" =
// StockService.receive). Expected: both units accepted (outboxes empty), the server raises ONE duplicateSerial issue,
// both phones pull it into "စစ်ရန်" (syncIssues), both keep the two in-stock rows; resolving on A reaches B.
// BUG-15 server round trip (TC-SYNC-NEW-6): A's first count of an untracked batch product (sold 1, counted 20 into a new
// batch) is accepted and B shows 20 / batch 20.
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
import 'package:zaypos_app/features/sync/domain/sync_labels.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live: same IMEI received offline on A and B → one duplicateSerial issue on both phones; opening count reaches B',
      () async {
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
        rawPhone: phone!, otp: otp!, shopName: 'QA live r4', templateId: 'phone', pin: '135790');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();
    final ph = Product(id: newId(), tenantId: tid, name: 'QA Redmi live r4', cost: 400000, price: 450000, category: 'ဖုန်း',
        tint: 0xFFDBEAFE, initial: 'R', createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(ph, serials: [
      ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: '357000000000001',
          status: SerialStatus.inStock, createdAt: t, updatedAt: t),
    ], initialStock: [restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(1), note: 'initial')]);
    final med = Product(id: newId(), tenantId: tid, name: 'QA untracked med live r4', cost: 100, price: 150,
        category: 'ဆေး', tint: 0xFFDBEAFE, initial: 'M', createdAt: t, updatedAt: t, expiryAlertDays: 30);
    await a.read(productServiceProvider).create(med);
    await sync(a);
    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);

    // Both offline: each receives IMEI 357000000000009 for the same product (own row ids).
    const dup = '357000000000009';
    await a.read(stockServiceProvider).receive(productId: ph.id, qtyMilli: Qty.units(1), serials: [dup]);
    await b.read(stockServiceProvider).receive(productId: ph.id, qtyMilli: Qty.units(1), serials: [dup]);
    // A: untracked medicine sold once, then the first count 20 into a new batch (BUG-15 path).
    await a.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: med.id, variantId: null, batchId: null, serialId: null, name: med.name, qtyMilli: 1000, price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    final first = ProductBatch(id: newId(), tenantId: tid, productId: med.id, batchNo: 'FIRST', qtyMilli: Qty.units(20),
        expiryDate: DateTime.utc(2028, 6, 30), createdAt: nowUtc(), updatedAt: nowUtc());
    await a.read(stockServiceProvider).receive(productId: med.id, qtyMilli: Qty.units(20), newBatch: first, openingCount: true);
    expect((await outbox(dbOf(a))).map((u) => u.kind), ['restock', 'checkout', 'stockAdjust']);

    await sync(a);
    await sync(b);
    await sync(a);

    for (final (name, c) in [('A', a), ('B', b)]) {
      final issues = await dbOf(c).select(dbOf(c).syncIssues).get();
      final dupIssues = issues.where((i) => i.kind == 'duplicateSerial').toList();
      expect(dupIssues, hasLength(1), reason: 'phone $name: ONE duplicateSerial in "စစ်ရန်" (all: ${issues.map((i) => i.kind)})');
      expect(dupIssues.single.detail, contains(dup));
      expect(dupIssues.single.resolvedAt, isNull);
      expect(issueKindLabel('duplicateSerial'), 'IMEI / Serial တူ ဖုန်း နှစ်လုံး stock ထဲ ရှိနေ');
      final rows = (await c.read(productRepositoryProvider).watchSerials(ph.id).first).where((s) => s.serial == dup);
      expect(rows.map((s) => s.status), [SerialStatus.inStock, SerialStatus.inStock], reason: 'phone $name keeps both rows');
      expect(await stockOf(c, ph.id), Qty.units(3), reason: 'phone $name');
      expect(issues.where((i) => i.kind == 'negativeStock'), isEmpty, reason: 'opening count must not raise negativeStock');
    }

    // BUG-15 on B: the medicine shows what A counted, all of it in batch FIRST.
    expect(await stockOf(b, med.id), Qty.units(20));
    final batchesB = await b.read(productRepositoryProvider).watchBatches(med.id).first;
    expect(batchesB.map((x) => (x.batchNo, x.qtyMilli)), [('FIRST', Qty.units(20))]);

    // Owner marks it checked on A → B pulls it resolved.
    final issueId = (await dbOf(a).select(dbOf(a).syncIssues).get()).singleWhere((i) => i.kind == 'duplicateSerial').id;
    await a.read(syncEngineProvider).resolveIssue(issueId);
    await sync(b);
    final onB = (await dbOf(b).select(dbOf(b).syncIssues).get()).singleWhere((i) => i.id == issueId);
    expect(onB.resolvedAt, isNotNull, reason: 'resolved on A, pulled by B');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
