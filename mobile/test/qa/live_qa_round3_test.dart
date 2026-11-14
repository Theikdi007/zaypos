// QA round 3 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round3_test.dart
// TC-SYNC-NEW-3 / -4: phone A receives goods as new IMEIs and as a new batch with expiry ("Stock ဖြည့်မယ်" =
// StockService.receive), adds an IMEI + clears the low alert in the edit form (ProductService.update); the real server
// accepts every unit and phone B pulls the IMEIs / batch / stock / lowAlert 0; B sells a received IMEI and A sees it sold.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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

  test('live: restock units with new IMEIs / a new batch and the edit-form unit reach phone B; B sells a received IMEI',
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
          reason: 'every unit must be accepted by the real server');
    }

    Future<int> stockOf(ProviderContainer c, String productId) async {
      final rows = await (dbOf(c).select(dbOf(c).stockMovements)
            ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull()))
          .get();
      return rows.fold<int>(0, (a, m) => a + m.qtyMilli);
    }

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r3', templateId: 'phone', pin: '135790');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();

    // A: an IMEI product (1 phone in stock) and a batch product (B1: 2).
    final ph = Product(id: newId(), tenantId: tid, name: 'QA Galaxy live', cost: 400000, price: 450000, category: 'ဖုန်း',
        tint: 0xFFDBEAFE, initial: 'G', createdAt: t, updatedAt: t, lowAlertMilli: 2000);
    final s1 = ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: '356000000000001',
        status: SerialStatus.inStock, createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(ph, serials: [s1], initialStock: [
      restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(1), note: 'initial'),
    ]);
    final med = Product(id: newId(), tenantId: tid, name: 'QA Amoxicillin live', cost: 100, price: 150, category: 'ဆေး',
        tint: 0xFFDBEAFE, initial: 'A', createdAt: t, updatedAt: t);
    final b1 = ProductBatch(id: newId(), tenantId: tid, productId: med.id, batchNo: 'B1', qtyMilli: 0,
        expiryDate: DateTime.utc(2030, 6, 30), createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(med, batches: [b1], initialStock: [
      restockMovement(tenantId: tid, productId: med.id, batchId: b1.id, qtyMilli: Qty.units(2), note: 'initial'),
    ]);
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);

    // A: "Stock ဖြည့်မယ်" — 2 new IMEIs; a new batch B2 (exp 2027-03-31) of 12. Edit form — 1 more IMEI, low alert cleared.
    final stock = a.read(stockServiceProvider);
    await stock.receive(productId: ph.id, qtyMilli: Qty.units(2), serials: ['356000000000002', '356000000000003']);
    final b2 = ProductBatch(id: newId(), tenantId: tid, productId: med.id, batchNo: 'B2', qtyMilli: Qty.units(12),
        expiryDate: DateTime.utc(2027, 3, 31), createdAt: nowUtc(), updatedAt: nowUtc());
    await stock.receive(productId: med.id, qtyMilli: Qty.units(12), newBatch: b2);
    final t2 = nowUtc();
    await a.read(productServiceProvider).update(ph.copyWith(lowAlertMilli: 0), serials: [
      ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: '356000000000004',
          status: SerialStatus.inStock, createdAt: t2, updatedAt: t2),
    ]);
    expect((await outbox(dbOf(a))).map((u) => u.kind), ['restock', 'restock', 'upsertProduct']);
    await sync(a);
    await sync(b);

    // B: same IMEIs (all in stock), same batches with the expiry date, same stock, low alert 0.
    final serialsB = await b.read(productRepositoryProvider).watchSerials(ph.id).first;
    expect({for (final s in serialsB) s.serial: s.status}, {
      '356000000000001': SerialStatus.inStock,
      '356000000000002': SerialStatus.inStock,
      '356000000000003': SerialStatus.inStock,
      '356000000000004': SerialStatus.inStock,
    });
    final batchesB = await b.read(productRepositoryProvider).watchBatches(med.id).first;
    expect({for (final x in batchesB) x.batchNo: (x.qtyMilli, x.expiryDate?.toUtc(), x.isExpired(DateTime.now()))}, {
      'B1': (Qty.units(2), DateTime.utc(2030, 6, 30), false),
      'B2': (Qty.units(12), DateTime.utc(2027, 3, 31), false),
    });
    expect(await stockOf(b, ph.id), Qty.units(4));
    expect(await stockOf(b, med.id), Qty.units(14));
    expect(await stockOf(a, ph.id), await stockOf(b, ph.id));
    final phOnB = await (dbOf(b).select(dbOf(b).products)..where((x) => x.id.equals(ph.id))).getSingle();
    expect(phOnB.lowAlertMilli, 0, reason: 'cleared alert reaches the other phone');

    // B sells received IMEI …003 and a box from B2; A pulls: that IMEI is sold, B2 = 11.
    final s3 = serialsB.singleWhere((s) => s.serial == '356000000000003');
    final b2OnB = batchesB.singleWhere((x) => x.batchNo == 'B2');
    final sale = await b.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: ph.id, variantId: null, batchId: null, serialId: s3.id, name: 'QA Galaxy live · IMEI ${s3.serial}',
          qtyMilli: 1000, price: 450000, cost: 400000),
      (productId: med.id, variantId: null, batchId: b2OnB.id, serialId: null, name: 'QA Amoxicillin live · Batch B2',
          qtyMilli: 1000, price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    expect(sale.no, startsWith('B-'));
    await sync(b);
    await sync(a);
    final s3OnA = (await a.read(productRepositoryProvider).watchSerials(ph.id).first).singleWhere((s) => s.id == s3.id);
    expect(s3OnA.status, SerialStatus.sold);
    final b2OnA = (await a.read(productRepositoryProvider).watchBatches(med.id).first).singleWhere((x) => x.id == b2.id);
    expect(b2OnA.qtyMilli, Qty.units(11));
    expect(await stockOf(a, ph.id), Qty.units(3));
    final issues = await dbOf(a).select(dbOf(a).syncIssues).get();
    expect(issues, isEmpty, reason: 'no serialDoubleSold / negativeStock / clockSkew for a normal flow');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
