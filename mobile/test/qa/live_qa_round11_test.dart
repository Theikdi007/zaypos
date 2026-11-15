// QA round 11 — live: BUG-32 (17180db), BUG-33 (ae22869) and the duplicate-barcode auto-close (1420ee8) against the REAL
// API and a scratch database, two phones of one shop.
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   flutter test test/qa/live_qa_round11_test.dart
//
// Phone A's network is made flaky by a wrapper around the app's own DioSyncApi (push / pull throw a network error while
// a flag is set), so the real engine runs its back-off path: "void fails to send, next pull must not undo it".
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/reports/data/report_repository.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import '../drift_helpers.dart';

class _Flaky implements SyncApi {
  _Flaky(this.inner);
  final SyncApi inner;
  bool pushFails = false;
  int pullFailures = 0;

  @override
  Future<PushResult> push(String deviceId, List<PushUnit> units) {
    if (pushFails) throw const ApiError.network();
    return inner.push(deviceId, units);
  }

  @override
  Future<PullPage> pull(String cursor, {int limit = 500}) {
    if (pullFailures > 0) {
      pullFailures--;
      throw const ApiError.network();
    }
    return inner.pull(cursor, limit: limit);
  }

  @override
  Future<Map<String, dynamic>> resolveIssue(String id) => inner.resolveIssue(id);
}

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('TC-SYNC-NEW-27 live r11: (1) duplicate barcode fixed on B → closed "fixed" on both phones, a later re-duplicate is a NEW open '
      'issue; (2) B edits a customer (BUG-33 unit) while A has an older unsent edit: A skips B\'s copy, sends, pulls '
      'again and converges to B\'s; (3) A sells, the pull drops, A voids, the void push fails, the next pull brings the '
      'unvoided sale → still voided, today 0; after the send A = server; (4) nothing duplicated or re-raised', () async {
    final dbs = <AppDatabase>[];
    final containers = <ProviderContainer>[];
    final flaky = <ProviderContainer, _Flaky>{};
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
      late final ProviderContainer c;
      c = ProviderContainer(overrides: [
        ...driftOverrides(db, boot, store),
        apiBaseUrlProvider.overrideWithValue(base!),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        syncApiProvider.overrideWith((ref) => flaky[c] = _Flaky(DioSyncApi(ref.watch(apiDioProvider)))),
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
        rawPhone: phone!, otp: otp!, shopName: 'QA live r11', templateId: 'grocery', pin: '864200');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '864200');
    await sync(b);
    final aDb = dbOf(a), bDb = dbOf(b);
    Future<List<SyncIssueRow>> dupIssues(AppDatabase db) => (db.select(db.syncIssues)
          ..where((i) => i.kind.equals('duplicateBarcode'))
          ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
        .get();
    String state(SyncIssueRow i) => i.resolvedAt == null ? 'open' : (i.data?.contains('"resolution":"fixed"') == true ? 'fixed' : 'owner');

    // ---- (1) duplicate barcode, two phones
    Product product(String name, String? barcode, {int cost = 100}) {
      final t = nowUtc();
      return Product(id: newId(), tenantId: tid, name: name, cost: cost, price: 150, category: 'x', barcode: barcode,
          tint: 0xFFDBEAFE, initial: 'Q', createdAt: t, updatedAt: t);
    }

    const x = '8850000011101', y = '8850000011102';
    final p1 = product('QA r11 Coke A', x);
    await a.read(productServiceProvider).create(p1);
    await sync(a);
    await sync(b);
    final p2 = product('QA r11 Coke B', x);
    await b.read(productServiceProvider).create(p2);
    await sync(b);
    await sync(b);
    await sync(a);
    expect(((await dupIssues(aDb)).map(state).toList(), (await dupIssues(bDb)).map(state).toList()).toString(), "([open], [open])",
        reason: 'setup: one open duplicateBarcode on each phone');

    await b.read(productServiceProvider).update(p2.copyWith(barcode: () => y, updatedAt: nowUtc()));
    await sync(b);
    await sync(a);
    final closed = ((await dupIssues(aDb)).map(state).toList(), (await dupIssues(bDb)).map(state).toList());
    // ignore: avoid_print
    print('r11 (1) after B changed the barcode: A=${closed.$1} B=${closed.$2}');
    expect(closed.$1, ['fixed']);
    expect(closed.$2, ['fixed']);

    await a.read(productServiceProvider).update(p1.copyWith(barcode: () => y, updatedAt: nowUtc()));
    await sync(a);
    await sync(a);
    await sync(b);
    final again = ((await dupIssues(aDb)).map(state).toList(), (await dupIssues(bDb)).map(state).toList());
    // ignore: avoid_print
    print('r11 (1) after A re-duplicated (barcode $y): A=${again.$1} B=${again.$2}');
    expect(again.$1, ['fixed', 'open']);
    expect(again.$2, ['fixed', 'open']);

    // ---- (2) customer: B's newer edit (BUG-33 path) vs A's older unsent edit
    final t0 = nowUtc();
    final cu = Customer(id: newId(), tenantId: tid, name: 'QA r11 Daw Mya', phone: '09790011101', address: 'Bahan',
        creditLimit: 50000, createdAt: t0, updatedAt: t0);
    await a.read(customerServiceProvider).create(cu);
    await sync(a);
    await sync(b);
    final fa = flaky[a]!;
    fa.pushFails = true;
    final aEngine = a.read(syncEngineProvider);
    await a.read(customerServiceProvider).update(cu.copyWith(name: 'QA r11 Daw Mya (A)'));
    await aEngine.syncNow(); // push fails → back-off
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final bRow = await (bDb.select(bDb.customers)..where((x) => x.id.equals(cu.id))).getSingle();
    await b.read(customerServiceProvider).update(Customer(id: cu.id, tenantId: tid, name: 'QA r11 Daw Mya (B)',
        phone: '09790011102', address: null, creditLimit: 20000, createdAt: bRow.createdAt, updatedAt: bRow.updatedAt));
    await sync(b);
    await aEngine.syncNow(); // within the back-off: pull only → B's copy must be skipped
    final skippedA = await (aDb.select(aDb.customers)..where((x) => x.id.equals(cu.id))).getSingle();
    final keys = await aDb.readState(SyncStateKeys.repullKeys);
    // ignore: avoid_print
    print('r11 (2) A while its edit is unsent: name=${skippedA.name} repullKeys=$keys');
    expect(skippedA.name, 'QA r11 Daw Mya (A)', reason: 'the pull must not overwrite A\'s unsent edit');
    expect(keys, contains('customers:${cu.id}'));
    fa.pushFails = false;
    await sync(a);
    await sync(a);
    final convergedA = await (aDb.select(aDb.customers)..where((x) => x.id.equals(cu.id))).getSingle();
    final raw = await a.read(syncApiProvider).pull('0', limit: 1000);
    final serverCu = raw.changes['customers']!.singleWhere((r) => r['id'] == cu.id);
    // ignore: avoid_print
    print('r11 (2) after A sent: A=(${convergedA.name}, ${convergedA.phone}, ${convergedA.address}, ${convergedA.creditLimit}) '
        'server=(${serverCu['name']}, ${serverCu['phone']}, ${serverCu['address']}, ${serverCu['creditLimit']})');
    expect((convergedA.name, convergedA.phone, convergedA.address, convergedA.creditLimit),
        (serverCu['name'], serverCu['phone'], serverCu['address'], serverCu['creditLimit']), reason: 'A = server');
    expect(serverCu['name'], 'QA r11 Daw Mya (B)', reason: 'last writer (B) wins on the server');

    // ---- (3) void fails to send; the next pull must not undo it
    final tea = product('QA r11 tea', null);
    await a.read(productServiceProvider).create(tea, initialStock: [
      restockMovement(tenantId: tid, productId: tea.id, qtyMilli: Qty.units(5)),
    ]);
    await sync(a);
    final sale = await a.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: tea.id, variantId: null, batchId: null, serialId: null, name: tea.name, qtyMilli: Qty.units(2), price: 150,
        cost: 100),
    ], method: PaymentMethod.cash));
    fa.pullFailures = 1;
    await aEngine.syncNow(manual: true); // checkout applied; the pull drops
    expect(await aDb.select(aDb.outbox).get(), isEmpty);
    Future<int> today(ProviderContainer c) async =>
        (await c.read(reportRepositoryProvider).watchReport(ReportPeriod.today).first).summary.sales;
    expect(await today(a), 300);
    fa.pushFails = true;
    await a.read(voidSaleServiceProvider).setVoided(sale.id, true);
    await aEngine.syncNow(); // the void push fails
    await aEngine.syncNow(); // within the back-off: pull only (brings the unvoided sale)
    final duringSale = await (aDb.select(aDb.sales)..where((s) => s.id.equals(sale.id))).getSingle();
    final duringKeys = await aDb.readState(SyncStateKeys.repullKeys);
    // ignore: avoid_print
    print('r11 (3) during: voidedAt=${duringSale.voidedAt} today=${await today(a)} outbox='
        '${(await aDb.select(aDb.outbox).get()).map((o) => o.kind)} repullKeys has sale=${duringKeys?.contains(sale.id)}');
    expect(duringSale.voidedAt, isNotNull, reason: 'the pull must not undo the unsent void');
    expect(await today(a), 0);
    expect(duringKeys, contains('sales:${sale.id}'), reason: 'the pull really brought the sale (it was skipped)');
    fa.pushFails = false;
    await sync(a);
    await sync(a);
    await sync(b);

    // ---- (4) A and B = the server, nothing duplicated or re-raised
    final all = await a.read(syncApiProvider).pull('0', limit: 5000);
    final serverSale = all.changes['sales']!.singleWhere((r) => r['id'] == sale.id);
    expect(serverSale['voidedAt'], isNotNull);
    for (final (name, c) in [('A', a), ('B', b)]) {
      final db = dbOf(c);
      final s = await (db.select(db.sales)..where((x) => x.id.equals(sale.id))).getSingle();
      final counts = {
        'sales': (await db.select(db.sales).get()).length,
        'saleLines': (await db.select(db.saleLines).get()).length,
        'payments': (await db.select(db.payments).get()).length,
        'stockMovements': (await db.select(db.stockMovements).get()).length,
        'customers': (await db.select(db.customers).get()).length,
        'products': (await db.select(db.products).get()).length,
        'syncIssues': (await db.select(db.syncIssues).get()).length,
      };
      final server = {for (final k in counts.keys) k: (all.changes[k] ?? const []).length};
      final stock = (await (db.select(db.stockMovements)..where((m) => m.productId.equals(tea.id))).get())
          .fold<int>(0, (x, m) => x + m.qtyMilli);
      // ignore: avoid_print
      print('r11 (4) $name: voided=${s.voidedAt != null} today=${await today(c)} stock=${Qty.format(stock)} counts=$counts '
          'server=$server issues=${(await dupIssues(db)).map(state)}');
      expect(s.voidedAt, isNotNull);
      expect(await today(c), 0);
      expect(stock, Qty.units(5));
      expect(counts, server, reason: '$name: same rows as the server, no duplicates');
      expect((await dupIssues(db)).map(state).toList(), ['fixed', 'open'], reason: '$name: nothing re-raised');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
