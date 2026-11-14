// QA round 2 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round2_test.dart
// TC-DEBT-NEW-4: both phones reverse the same wrong payment offline → one reversal everywhere, no rejected unit.
// TC-PROD-NEW-3 / TC-SYNC-06: an edit made with the edit form's service call reaches the other phone.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/debt_repository.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live: two phones reverse one payment offline → one reversal; a product edit reaches the other phone', () async {
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

    Future<int> balance(ProviderContainer c, String customerId) async =>
        (await c.read(debtRepositoryProvider).watchBalances().first)[customerId] ?? 0;

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r2', templateId: 'grocery', pin: '135790');
    await sync(a);
    final tenantId = a.read(tenantIdProvider);

    // A: customer with opening debt 52,000, a product, and a WRONG 20,000 KBZ payment.
    final t = nowUtc();
    final cust = Customer(id: newId(), tenantId: tenantId, name: 'ဒေါ်ခင်မာ', phone: '', createdAt: t, updatedAt: t);
    await a.read(customerServiceProvider).create(cust, openingBalance: 52000);
    final p = Product(id: newId(), tenantId: tenantId, name: 'ရေသန့် 1L', cost: 450, price: 600, category: 'General',
        tint: 0xFFDBEAFE, initial: 'ရ', createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(p);
    final pay = await a.read(customerServiceProvider)
        .recordPayment(tenantId: tenantId, customerId: cust.id, amount: 20000, method: PaymentMethod.kbz);
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    expect(await balance(b, cust.id), 32000);

    // Both reverse the payment while offline (no sync in between).
    final payOnB = (await b.read(debtRepositoryProvider).watchAll().first).firstWhere((e) => e.id == pay.id);
    final revA = await a.read(customerServiceProvider).reversePayment(pay);
    final revB = await b.read(customerServiceProvider).reversePayment(payOnB);
    expect(revA!.id, revB!.id);

    await sync(a);
    await sync(b); // B's reversal has the id the server already has: kept once, B's unit not rejected
    await sync(a);
    for (final c in [a, b]) {
      final rows = await (dbOf(c).select(dbOf(c).debtEntries)..where((e) => e.customerId.equals(cust.id))).get();
      expect(rows.where((e) => e.id == revA.id), hasLength(1));
      expect(rows.where((e) => e.id == pay.id && e.deletedAt == null), hasLength(1));
      expect(await balance(c, cust.id), 52000, reason: '52,000 − 20,000 + 20,000 once');
    }
    expect(rowsTypes(await (dbOf(b).select(dbOf(b).debtEntries)..where((e) => e.customerId.equals(cust.id))).get()),
        {'adjustment': 2, 'payment': 1});

    // A edits the product (what the edit form saves); B pulls the new name and price.
    await a.read(productServiceProvider).update(p.copyWith(name: 'ရေသန့် 1 လီတာ', price: 700));
    await sync(a);
    await sync(b);
    final onB = await (dbOf(b).select(dbOf(b).products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((onB.name, onB.price, onB.createdAt.toUtc()), ('ရေသန့် 1 လီတာ', 700, t));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}

Map<String, int> rowsTypes(List<DebtEntryRow> rows) {
  final m = <String, int>{};
  for (final r in rows) {
    m[r.type.name] = (m[r.type.name] ?? 0) + 1;
  }
  return m;
}
