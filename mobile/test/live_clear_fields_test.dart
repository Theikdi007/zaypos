import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/data/unit_recorder.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

import 'drift_helpers.dart';

/// BUG-31 live, two phones of one shop, against a running backend (skipped otherwise):
///   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
///   flutter test test/live_clear_fields_test.dart
/// Phone B clears barcode, wholesale price, expiry days and a credit limit → phone A shows them empty;
/// clearing a duplicate barcode on B resolves the duplicate on A.
void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('B clears fields → A shows them empty; a duplicate barcode cleared on B is gone on A', () async {
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
      final db = dbs[containers.indexOf(c)];
      expect((await db.select(db.outbox).get()).map((o) => '${o.kind} ${o.status.name} ${o.rejectReason}'), isEmpty);
    }

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'Live clear fields', templateId: 'pharmacy', pin: '135790');
    await sync(a);
    final tenantId = a.read(tenantIdProvider);
    final t = nowUtc();
    Product product(String name, String barcode) => Product(
          id: newId(), tenantId: tenantId, name: name, cost: 100, price: 150, category: 'ဆေး', barcode: barcode,
          wholesalePrice: 140, expiryAlertDays: 30, tint: 0, initial: 'ဆ', createdAt: t, updatedAt: t,
        );
    final p = product('ပါရာစီတမော', '8850000031001');
    final dupA = product('ဗီတာမင် က', '8850000031002'), dupB = product('ဗီတာမင် ခ', '8850000031002');
    for (final x in [p, dupA, dupB]) {
      await a.read(productServiceProvider).create(x);
    }
    final customer = Customer(id: newId(), tenantId: tenantId, name: 'မမ', phone: '09790031001', creditLimit: 50000,
        createdAt: t, updatedAt: t);
    await a.read(customerServiceProvider).create(customer);
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    final aDb = dbs[0], bDb = dbs[1];

    // ---- phone B clears the fields (edit form → empty fields / "သက်တမ်း မမှတ်ပါ"), and one duplicate barcode
    await b.read(productServiceProvider).update(
        p.copyWith(barcode: () => null, wholesalePrice: () => null, expiryAlertDays: () => null, updatedAt: nowUtc()));
    await b.read(productServiceProvider).update(dupB.copyWith(barcode: () => null, updatedAt: nowUtc()));
    // The app has no customer edit screen yet: record the upsertCustomer unit such an edit sends (creditLimit null).
    await b.read(unitOfWorkProvider).run(UnitKind.upsertCustomer, () async {
      final row = await (bDb.select(bDb.customers)..where((x) => x.id.equals(customer.id))).getSingle();
      final cleared = row.copyWith(creditLimit: const Value(null), updatedAt: nowUtc());
      await bDb.update(bDb.customers).replace(cleared);
      UnitRecorder.require().record(WireTable.customers, customerWire(cleared));
    });
    await sync(b);
    await sync(a);

    final onA = await (aDb.select(aDb.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect((onA.barcode, onA.wholesalePrice, onA.expiryAlertDays), (null, null, null), reason: 'cleared on B → empty on A');
    expect((await (aDb.select(aDb.customers)..where((x) => x.id.equals(customer.id))).getSingle()).creditLimit, isNull);
    final withDup = await (aDb.select(aDb.products)..where((x) => x.barcode.equals('8850000031002'))).get();
    expect(withDup.map((x) => x.id), [dupA.id], reason: 'the duplicate is resolved on A too: one product keeps the barcode');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
