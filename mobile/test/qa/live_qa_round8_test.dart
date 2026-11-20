// QA round 8 — live: two phones of one shop against the REAL API (scratch database only).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round8_test.dart
// e0ea12b scan lookup across phones (TC-SYNC-NEW-13):
// - decision (a): a duplicate barcode saved on A (warned, "ဒီအတိုင်း သိမ်းမယ်" = the same ProductService.create unit, see
//   m/qa/qa_round8_scan_drift_test.dart) is accepted by the server, flagged ONCE as duplicateBarcode (README §3.4), and
//   reaches B with both products, so B's POS lookup (`productsByBarcode`, the function the picker uses) finds both;
// - decision (c): B's IMEI lookup (`watchSerialRows`, used by the POS scan) finds A's in-stock IMEI; B sells it with that
//   serial row; after sync A sees it sold (its scan would now offer "ပစ္စည်းအသစ်"), no issue; both phones selling the
//   same IMEI offline by scan → serialDoubleSold (server rule unchanged).
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../live_removed_phone_sign_in.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live: duplicate barcode from A → one duplicateBarcode issue, B finds both; IMEI found by B\'s scan lookup, sold on '
      'B, sold on A after sync; both phones scan-selling one IMEI offline → serialDoubleSold', () async {
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

    Future<List<SyncIssueRow>> issues(ProviderContainer c) => dbOf(c).select(dbOf(c).syncIssues).get();

    /// What the POS scan does first in a phone shop: in-stock rows with this IMEI.
    Future<List<ProductSerial>> scanSerial(ProviderContainer c, String imei) async =>
        (await c.read(productRepositoryProvider).watchSerialRows(imei).first)
            .where((s) => s.status == SerialStatus.inStock)
            .toList();

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r8', templateId: 'phone', pin: '135790');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();

    const code = '8850000088001';
    Product plain(String name, String? barcode) => Product(id: newId(), tenantId: tid, name: name, cost: 1000, price: 1500,
        category: 'x', barcode: barcode, tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t);
    final one = plain('QA r8 dup one', code), two = plain('QA r8 dup two', code);
    await a.read(productServiceProvider).create(one);
    await a.read(productServiceProvider).create(two);

    const m1 = '359880000000001', m2 = '359880000000002';
    final ph = Product(id: newId(), tenantId: tid, name: 'QA r8 phone', cost: 400000, price: 450000, category: 'ဖုန်း',
        barcode: '6901443088000', tint: 0xFFDBEAFE, initial: 'P', createdAt: t, updatedAt: t);
    ProductSerial row(String imei) => ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: imei,
        status: SerialStatus.inStock, createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(ph, serials: [row(m1), row(m2)],
        initialStock: [restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(2), note: 'initial')]);
    await sync(a);

    final dupA = (await issues(a)).where((i) => i.kind == 'duplicateBarcode').toList();
    expect(dupA, hasLength(1), reason: 'README §3.4: flagged once (the 2nd product)');
    expect(dupA.single.detail, contains(code));
    // ignore: avoid_print
    print('TC-SYNC-NEW-13 duplicateBarcode detail from the server: "${dupA.single.detail}"');

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    final onB = await settled(b, productsProvider);
    final matches = productsByBarcode(onB, code, b.read(syncLimitsProvider)).map((v) => v.id).toSet();
    expect(matches, {one.id, two.id}, reason: 'decision (b): B\'s POS picker gets both');
    expect((await issues(b)).where((i) => i.kind == 'duplicateBarcode'), hasLength(1), reason: 'B sees the issue too');

    // IMEI scan on B
    final foundB = await scanSerial(b, m1);
    expect(foundB.map((s) => s.productId), [ph.id], reason: 'B\'s scan finds A\'s in-stock IMEI');
    Future<Sale> sellOn(ProviderContainer c, String serialId) => c.read(checkoutServiceProvider).checkout(CheckoutRequest(
        lines: [(productId: ph.id, variantId: null, batchId: null, serialId: serialId, name: ph.name, qtyMilli: 1000,
            price: 450000, cost: 400000)],
        method: PaymentMethod.cash));
    await sellOn(b, foundB.single.id);
    await sync(b);
    await sync(a);
    expect(await scanSerial(a, m1), isEmpty, reason: 'A: m1 sold → its scan now offers "ပစ္စည်းအသစ်"');
    expect((await a.read(productRepositoryProvider).watchSerialRows(m1).first).single.status, SerialStatus.sold);
    expect((await issues(a)).map((i) => i.kind).where((k) => k != 'duplicateBarcode'), isEmpty, reason: 'no other issue');

    // both phones scan-sell m2 offline
    final m2A = (await scanSerial(a, m2)).single, m2B = (await scanSerial(b, m2)).single;
    expect(m2A.id, m2B.id);
    await sellOn(a, m2A.id);
    await sellOn(b, m2B.id);
    await sync(a);
    await sync(b);
    await sync(a);
    for (final (name, c) in [('A', a), ('B', b)]) {
      expect((await issues(c)).map((i) => i.kind), contains('serialDoubleSold'), reason: 'phone $name');
      expect(await scanSerial(c, m2), isEmpty, reason: 'phone $name: m2 not in stock');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
