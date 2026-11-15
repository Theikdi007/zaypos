// QA round 10 — live: BUG-31 (8b513b5) against the REAL API and a scratch database (two phones of one shop).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round10_test.dart
//
// Owner: "a null/empty value from the server must overwrite the local value … Check both directions: the server pull
// response must include null fields (not omitted by JSON settings); a cleared field on push is sent as null and the
// server stores null. Live test with two phones: clear barcode, wholesale price, expiry days and credit limit on phone
// B; phone A shows them empty. Also: clearing a duplicate barcode on one phone resolves it on all phones."
// What the developer's m/live_clear_fields_test.dart does not do, and this file does: warrantyMonths, customer address /
// note; the RAW pull JSON the real server sends (keys present with null, read through the app's own DioSyncApi); the
// duplicateBarcode ISSUE on both phones after the barcode is cleared (observed and printed; then resolved by the owner
// with "စစ်ပြီး" — POST /sync/issues/{id}/resolve — and the resolution reaches the other phone).
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

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live BUG-31: B clears barcode / wholesale / warranty / expiry days and a customer\'s address / note / credit '
      'limit → the server stores NULL and its pull JSON carries explicit nulls → A shows them empty; a duplicate barcode '
      'cleared on B: one product per scan on both phones; the duplicateBarcode issue (observed) is resolved by the owner '
      'on B and the resolution reaches A', () async {
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
      final db = dbOf(c);
      expect((await db.select(db.outbox).get()).map((o) => '${o.kind} ${o.status.name} ${o.rejectReason}'), isEmpty);
    }

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r10', templateId: 'phone', pin: '864200');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();
    Product product(String name, String barcode) => Product(id: newId(), tenantId: tid, name: name, cost: 1000,
        price: 1500, category: 'x', barcode: barcode, wholesalePrice: 1400, warrantyMonths: 6, expiryAlertDays: 30,
        tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t);
    const dup = '8850000010202';
    final p = product('QA r10 charger', '8850000010201');
    final d1 = product('QA r10 cable A', dup), d2 = product('QA r10 cable B', dup);
    for (final x in [p, d1, d2]) {
      await a.read(productServiceProvider).create(x);
    }
    final cu = Customer(id: newId(), tenantId: tid, name: 'QA r10 Daw Mya', phone: '09790010006', address: 'Bahan',
        creditLimit: 50000, note: 'VIP', createdAt: t, updatedAt: t);
    await a.read(customerServiceProvider).create(cu);
    await sync(a);
    await sync(a); // pull the issue the push raised

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '864200');
    await sync(b);
    final aDb = dbOf(a), bDb = dbOf(b);
    Future<List<SyncIssueRow>> dupIssues(AppDatabase db) =>
        (db.select(db.syncIssues)..where((i) => i.kind.equals('duplicateBarcode'))).get();
    final issuesBefore = (await dupIssues(aDb), await dupIssues(bDb));
    expect((issuesBefore.$1.length, issuesBefore.$2.length), (1, 1), reason: 'setup: one duplicateBarcode issue on each phone');

    // ---- phone B clears the fields (the edit form sends exactly this: m/qa/qa_round10_pull_null_test.dart TC-SYNC-NEW-18)
    await b.read(productServiceProvider).update(p.copyWith(barcode: () => null, wholesalePrice: () => null,
        warrantyMonths: () => null, expiryAlertDays: () => null, updatedAt: nowUtc()));
    await b.read(productServiceProvider).update(d2.copyWith(barcode: () => null, updatedAt: nowUtc()));
    // no customer edit screen in the app (TC-DEBT-NEW-6): the upsertCustomer unit such an edit would send
    await b.read(unitOfWorkProvider).run(UnitKind.upsertCustomer, () async {
      final row = await (bDb.select(bDb.customers)..where((x) => x.id.equals(cu.id))).getSingle();
      final cleared = row.copyWith(address: const Value(null), note: const Value(null), creditLimit: const Value(null),
          updatedAt: nowUtc());
      await bDb.update(bDb.customers).replace(cleared);
      UnitRecorder.require().record(WireTable.customers, customerWire(cleared));
    });
    await sync(b);

    // ---- the raw pull JSON of the real server, through the app's own API client (phone A's session)
    final raw = await a.read(syncApiProvider).pull('0', limit: 1000);
    final rp = raw.changes['products']!.singleWhere((r) => r['id'] == p.id);
    final rc = raw.changes['customers']!.singleWhere((r) => r['id'] == cu.id);
    final rawNulls = {
      for (final k in ['barcode', 'wholesalePrice', 'warrantyMonths', 'expiryAlertDays']) 'products.$k': (rp.containsKey(k), rp[k]),
      for (final k in ['address', 'note', 'creditLimit']) 'customers.$k': (rc.containsKey(k), rc[k]),
    };
    // ignore: avoid_print
    print('r10 raw pull: $rawNulls');
    expect(rawNulls.values.toSet(), {(true, null)}, reason: 'keys present, value null');

    await sync(a);
    final onA = await (aDb.select(aDb.products)..where((x) => x.id.equals(p.id))).getSingle();
    final cA = await (aDb.select(aDb.customers)..where((x) => x.id.equals(cu.id))).getSingle();
    expect({
      'barcode': onA.barcode, 'wholesalePrice': onA.wholesalePrice, 'warrantyMonths': onA.warrantyMonths,
      'expiryAlertDays': onA.expiryAlertDays, 'address': cA.address, 'note': cA.note, 'creditLimit': cA.creditLimit,
    }, {
      'barcode': null, 'wholesalePrice': null, 'warrantyMonths': null, 'expiryAlertDays': null, 'address': null,
      'note': null, 'creditLimit': null,
    }, reason: 'cleared on B → empty on A');
    for (final db in [aDb, bDb]) {
      final withDup = await (db.select(db.products)..where((x) => x.barcode.equals(dup))).get();
      expect(withDup.map((x) => x.id), [d1.id], reason: 'one product per scan of the old duplicate barcode');
    }

    // ---- the duplicateBarcode issue after the barcode was cleared: observed (owner decision), then resolved on B
    final afterA = await dupIssues(aDb), afterB = await dupIssues(bDb);
    // ignore: avoid_print
    print('r10 duplicateBarcode issue after B cleared the barcode: A open=${afterA.map((i) => i.resolvedAt == null)}, '
        'B open=${afterB.map((i) => i.resolvedAt == null)}');
    await b.read(syncEngineProvider).resolveIssue(afterB.single.id);
    await sync(a);
    final resolvedOnA = (await dupIssues(aDb)).single.resolvedAt;
    expect(resolvedOnA, isNotNull, reason: 'the owner marks it reviewed on B → A sees it resolved after a pull');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
