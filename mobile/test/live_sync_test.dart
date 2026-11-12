import 'dart:io';

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
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'drift_helpers.dart';

/// §9 integration, against a running backend (skipped otherwise):
///   ZAYPOS_LIVE_API=http://127.0.0.1:5076 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
///   flutter test test/live_sync_test.dart
/// Request a register OTP for a NEW phone first; the dev backend prints the code.
void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('two phones of one shop: A sells → B sees it; both sell one IMEI → serialDoubleSold', () async {
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

    Future<void> sync(ProviderContainer c) async {
      final e = c.read(syncEngineProvider);
      await e.syncNow(manual: true);
      expect(e.snapshot.lastError, isNull, reason: 'sync failed: ${e.snapshot.lastError}');
      final left = await dbs[containers.indexOf(c)].select(dbs[containers.indexOf(c)].outbox).get();
      expect(left.map((o) => '${o.kind}: ${o.status.name} ${o.rejectReason ?? ''}'), isEmpty,
          reason: 'every unit must be accepted by the real server');
    }

    // ---- phone A registers the shop and downloads it
    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'Live sync', templateId: 'phone', pin: '135790');
    expect(a.read(firstSyncDoneProvider), isFalse);
    await sync(a);
    expect(a.read(firstSyncDoneProvider), isTrue);
    expect(await dbs[0].select(dbs[0].tenantFeatureFlags).get(), isNotEmpty, reason: 'features pulled');
    final tenantId = a.read(tenantIdProvider);

    // ---- A adds a phone with one IMEI and 2 in stock
    final t = nowUtc();
    final product = Product(
      id: newId(), tenantId: tenantId, name: 'Redmi 13', cost: 400000, price: 450000, category: 'Phone',
      tint: 0xFFE0E7FF, initial: 'R', createdAt: t, updatedAt: t,
    );
    final serial = ProductSerial(
      id: newId(), tenantId: tenantId, productId: product.id, serial: '356938035643809', status: SerialStatus.inStock,
      createdAt: t, updatedAt: t,
    );
    await a.read(productServiceProvider).create(product, serials: [serial], initialStock: [
      restockMovement(tenantId: tenantId, productId: product.id, qtyMilli: Qty.units(2)),
    ]);
    await sync(a);

    // ---- phone B signs in to the same shop and downloads everything
    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    final bDb = dbs[1];
    expect((await (bDb.select(bDb.products)..where((p) => p.id.equals(product.id))).getSingle()).name, 'Redmi 13');
    expect((await bDb.select(bDb.devices).get()).map((d) => d.code).toSet(), {'A', 'B'});

    // ---- both sell the same IMEI before seeing each other's sale
    SaleLineDraftT line() => (
          productId: product.id, variantId: null, batchId: null, serialId: serial.id, name: 'Redmi 13',
          qtyMilli: 1000, price: 450000, cost: 400000,
        );
    final saleA = await a.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [line()], method: PaymentMethod.cash));
    final saleB = await b.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [line()], method: PaymentMethod.kbz));
    expect(saleA.no, startsWith('A-'));
    expect(saleB.no, startsWith('B-'));

    await sync(a); // A first: A keeps the serial
    await sync(b); // B: applied with serialDoubleSold, then pulls A's sale and the issue

    final bSales = (await bDb.select(bDb.sales).get()).map((s) => s.no).toSet();
    expect(bSales, containsAll([saleA.no, saleB.no]), reason: 'B sees A\'s sale');
    final issues = await bDb.select(bDb.syncIssues).get();
    expect(issues.map((i) => i.kind), contains('serialDoubleSold'));
    expect((await bDb.select(bDb.outbox).get()), isEmpty);
    final syncedB = await (bDb.select(bDb.sales)..where((s) => s.id.equals(saleB.id))).getSingle();
    expect(syncedB.syncedAt, isNotNull, reason: 'pulled back with the server arrival time');

    // ---- the owner resolves it from B; A sees it resolved
    final issue = issues.firstWhere((i) => i.kind == 'serialDoubleSold');
    await b.read(syncEngineProvider).resolveIssue(issue.id);
    await sync(a);
    final aDb = dbs[0];
    final onA = await (aDb.select(aDb.syncIssues)..where((i) => i.id.equals(issue.id))).getSingle();
    expect(onA.resolvedAt, isNotNull);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}

typedef SaleLineDraftT = ({
  String? productId,
  String? variantId,
  String? batchId,
  String? serialId,
  String name,
  int qtyMilli,
  int price,
  int cost,
});
