import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late TestShop shop;
  late FakeSyncApi api;
  late SyncStore store;
  late DateTime now;
  late List<String> ended;
  late int initialDone;

  setUp(() async {
    db = memoryDb();
    (c, shop) = await driftContainer(db);
    api = FakeSyncApi();
    store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    now = DateTime.utc(2026, 11, 12, 10);
    ended = [];
    initialDone = 0;
    await store.markInitialSyncDone(); // most tests: an already-downloaded shop
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  SyncEngine engine({Duration debounce = const Duration(milliseconds: 10)}) => SyncEngine(
        api: api,
        store: store,
        deviceId: shop.deviceId,
        clock: () => now,
        onSessionEnded: (code) async => ended.add(code),
        onInitialSyncDone: () => initialDone++,
        debounce: debounce,
      );

  final water = draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450);
  Future<Sale> sale() => sell(c, [water]);

  Product newProduct(String name, {DateTime? at}) {
    final t = at ?? nowUtc();
    return Product(
      id: newId(),
      tenantId: shop.tenantId,
      name: name,
      cost: 100,
      price: 150,
      category: 'General',
      tint: 0xFFE0F2F1,
      initial: 'P',
      createdAt: t,
      updatedAt: t,
    );
  }

  Future<void> addProduct(Product p) => c.read(productServiceProvider).create(p);

  Future<ProductRow?> localProduct(String id) =>
      (db.select(db.products)..where((x) => x.id.equals(id))).getSingleOrNull();

  Map<String, dynamic> serverProduct(String id, String name, DateTime updatedAt) => {
        ...productWire(ProductRow(
          id: id,
          tenantId: shop.tenantId,
          name: name,
          category: 'General',
          unit: '',
          cost: 100,
          price: 150,
          lowAlertMilli: 5000,
          tint: 1,
          initial: 'P',
          createdAt: updatedAt,
          updatedAt: updatedAt,
        )),
      };

  // ================================================================ push (§5.2)

  group('push', () {
    test('applied: the unit is sent with this device id and its outbox row is deleted', () async {
      await sale();
      final o = (await outbox(db)).single;

      await engine().syncNow();

      final sent = api.pushes.single.single;
      expect(api.pushDeviceIds.single, shop.deviceId);
      expect((sent.unitId, sent.kind), (o.unitId, 'checkout'));
      expect(jsonEncode(sent.rows), o.rowsJson);
      expect(sent.toJson()['clientTime'], endsWith('Z'));
      expect(await outbox(db), isEmpty);
      expect(api.pullCursors, isNotEmpty, reason: 'push before pull');
    });

    test('units go up oldest first, at most 50 per request', () async {
      for (var i = 0; i < 53; i++) {
        await c.read(customerServiceProvider).recordPayment(
            tenantId: shop.tenantId, customerId: SeedIds.aungKyaw, amount: 100 + i, method: PaymentMethod.cash);
      }
      final order = (await outbox(db)).map((o) => o.unitId).toList();

      await engine().syncNow();

      expect(api.pushes.map((p) => p.length), [50, 3]);
      expect([for (final p in api.pushes) ...p.map((u) => u.unitId)], order);
    });

    test('skipped voidSale: outbox row and its reversal ledger rows go; the voided sale stays', () async {
      final s = await sale();
      await engine().syncNow();
      final movementsBefore = (await db.select(db.stockMovements).get()).length;
      await c.read(voidSaleServiceProvider).setVoided(s.id, true);
      final voidUnit = SyncStore.rowsOf((await outbox(db)).single);
      expect(voidUnit[WireTable.stockMovements], hasLength(1));
      api.outcome = (u) => u.kind == 'voidSale' ? UnitOutcome.skipped : UnitOutcome.applied;

      await engine().syncNow();

      expect(await outbox(db), isEmpty);
      expect(await db.select(db.stockMovements).get(), hasLength(movementsBefore),
          reason: 'the void-return movement was not kept by the server');
      final local = await (db.select(db.sales)..where((x) => x.id.equals(s.id))).getSingle();
      expect(local.voidedAt, isNotNull, reason: 'its state already equals the server');
    });

    test('rejected: status + reason saved, later units are NOT sent — and it keeps blocking; pull still runs', () async {
      await addProduct(newProduct('first'));
      await addProduct(newProduct('second (bad)'));
      await addProduct(newProduct('third'));
      api.outcome = (u) => jsonEncode(u.rows).contains('second (bad)') ? UnitOutcome.rejected : UnitOutcome.applied;

      await engine().syncNow();

      final rows = await outbox(db);
      expect(rows.map((o) => o.status), [OutboxStatus.rejected, OutboxStatus.pending]);
      expect(rows.first.rejectReason, api.rejectReason);
      expect(api.pushes.single, hasLength(3), reason: 'one request; the server answered all three');
      // The third (pending) unit stays: it may depend on the rejected one.
      expect(SyncStore.rowsOf(rows.last)[WireTable.products].single['name'], 'third');

      final e = engine();
      api.pushes.clear();
      api.pullCursors.clear();
      await e.syncNow(manual: true);
      expect(api.pushes, isEmpty, reason: 'nothing is pushed past a rejected unit');
      expect(api.pullCursors, hasLength(1), reason: 'a blocked outbox still pulls');
    });

    test('network error: attempts++ and lastError; backoff 5 s → 30 s → 2 min → 10 min; manual sync ignores it', () async {
      await sale();
      final e = engine();
      api.pushErrors.addAll([const ApiError.network(), const ApiError(503, 'server')]);

      await e.syncNow();
      var o = (await outbox(db)).single;
      expect((o.attempts, o.lastError), (1, apiErrorMessage('network')));
      expect(e.snapshot.online, isFalse);
      expect(e.snapshot.lastError, apiErrorMessage('network'));
      expect(e.pushAfter, now.add(const Duration(seconds: 5)));
      expect(api.pullCursors, isEmpty, reason: 'offline: the cycle stops');

      now = now.add(const Duration(seconds: 4));
      await e.syncNow();
      expect(api.pushes, hasLength(1), reason: 'still backing off: no push');
      expect(api.pullCursors, hasLength(1), reason: 'backoff skips only the push; the pull still runs');

      now = now.add(const Duration(seconds: 2));
      await e.syncNow(); // 503
      o = (await outbox(db)).single;
      expect(o.attempts, 2);
      expect(e.pushAfter, now.add(const Duration(seconds: 30)));
      expect(api.pullCursors, hasLength(2), reason: 'a server error on push still lets the pull run');

      await e.syncNow(manual: true); // "ယခု sync လုပ်မယ်"
      expect(await outbox(db), isEmpty);
      expect(e.snapshot.lastError, isNull);
      expect(e.snapshot.online, isTrue);

      expect(
        [for (var n = 1; n <= 6; n++) SyncEngine.backoffFor(n)],
        [
          const Duration(seconds: 5),
          const Duration(seconds: 30),
          const Duration(minutes: 2),
          const Duration(minutes: 10),
          const Duration(minutes: 10),
          const Duration(minutes: 10),
        ],
      );
    });

    test('a revoked device (403) ends the session; the outbox is kept', () async {
      await sale();
      api.pushErrors.add(const ApiError(403, 'device_revoked'));
      await engine().syncNow();
      expect(ended, ['device_revoked']);
      expect(await outbox(db), hasLength(1));
    });

    test('single flight: triggers during a cycle join it and queue ONE more cycle', () async {
      await sale();
      api.delay = const Duration(milliseconds: 20);
      final e = engine();

      await Future.wait([e.syncNow(), e.syncNow(), e.syncNow(), e.syncNow()]);

      expect(api.pushes, hasLength(1), reason: 'the unit was pushed once');
      expect(api.pullCursors, hasLength(2), reason: 'first cycle + one queued cycle');
    });

    test('scheduleSoon is debounced: two triggers, one push after the delay', () async {
      final e = engine(debounce: const Duration(milliseconds: 30));
      await sale();
      e.scheduleSoon();
      e.scheduleSoon();
      expect(api.pushes, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await e.syncNow(); // joins / follows the scheduled cycle
      expect(api.pushes, hasLength(1));
    });

    test('the disabled engine (demo / signed out) never calls the server', () async {
      await sale();
      final e = SyncEngine.disabled();
      await e.syncNow(manual: true);
      e.scheduleSoon();
      expect(e.snapshot.enabled, isFalse);
      expect(api.pushes, isEmpty);
      expect(await outbox(db), hasLength(1));
    });
  });

  // ================================================================ merge (§5.3)

  group('merge rules', () {
    test('sales / lines / payments / movements / debt / issues: insert or replace (voidedAt and syncedAt from the server)', () async {
      final s = await sale();
      await engine().syncNow();
      final local = await (db.select(db.sales)..where((x) => x.id.equals(s.id))).getSingle();
      final synced = DateTime.utc(2026, 11, 12, 10, 0, 1);
      final voided = DateTime.utc(2026, 11, 12, 10, 5);
      api.pages.add(page({
        'sales': [
          {...saleWire(local), 'syncedAt': synced.toIso8601String(), 'voidedAt': voided.toIso8601String()},
        ],
        'syncIssues': [
          {
            'id': 'issue-1', 'tenantId': shop.tenantId, 'kind': 'negativeStock', 'entityTable': 'Products',
            'entityId': SeedIds.water, 'detail': 'stock -2', 'createdAt': synced.toIso8601String(),
            'updatedAt': synced.toIso8601String(),
          },
        ],
      }, cursor: '00000000000000A1'));

      await engine().syncNow();

      final merged = await (db.select(db.sales)..where((x) => x.id.equals(s.id))).getSingle();
      expect((merged.syncedAt, merged.voidedAt), (synced, voided));
      expect((await db.select(db.syncIssues).getSingle()).kind, 'negativeStock');
      expect(await store.cursor(), '00000000000000A1');
    });

    test('products: replaced when pulled.updatedAt >= local, kept when older', () async {
      final t = DateTime.utc(2026, 11, 1);
      final p = newProduct('local', at: t);
      await addProduct(p);
      await engine().syncNow(); // pushed: no unpushed edit any more

      api.pages.add(page({'products': [serverProduct(p.id, 'older', t.subtract(const Duration(minutes: 1)))]}, cursor: '1'));
      await engine().syncNow();
      expect((await localProduct(p.id))!.name, 'local');

      api.pages.add(page({'products': [serverProduct(p.id, 'same time', t)]}, cursor: '2'));
      await engine().syncNow();
      expect((await localProduct(p.id))!.name, 'same time');

      api.pages.add(page({'products': [serverProduct(p.id, 'newer', t.add(const Duration(minutes: 1)))]}, cursor: '3'));
      await engine().syncNow();
      expect((await localProduct(p.id))!.name, 'newer');

      final brandNew = newId();
      api.pages.add(page({'products': [serverProduct(brandNew, 'from phone B', t)]}, cursor: '4'));
      await engine().syncNow();
      expect((await localProduct(brandNew))!.name, 'from phone B');
    });

    test('a pending local edit is NOT overwritten by a pulled row, even a newer one', () async {
      final p = newProduct('my unpushed edit');
      await addProduct(p);
      api.pushErrors.add(const ApiError(503, 'server')); // push fails, pull runs
      api.pages.add(page({'products': [serverProduct(p.id, 'server', DateTime.utc(2100))]}, cursor: '1'));

      await engine().syncNow();

      expect((await localProduct(p.id))!.name, 'my unpushed edit');
      expect(await outbox(db), hasLength(1));
      expect(await store.cursor(), '1', reason: 'the page was still merged (other rows)');
    });

    test('customers and tenant features follow the same rule; features are keyed by featureKey', () async {
      final t = nowUtc();
      final customerId = newId();
      await c.read(customerServiceProvider).create(
            Customer(id: customerId, tenantId: shop.tenantId, name: 'local', phone: '', createdAt: t, updatedAt: t),
          );
      api.pushErrors.add(const ApiError(503, 'server'));
      api.pages.add(page({
        'customers': [
          {...customerWire(CustomerRow(id: customerId, tenantId: shop.tenantId, name: 'server', phone: '', createdAt: t, updatedAt: t.add(const Duration(hours: 1))))},
        ],
        'tenantFeatures': [
          {'tenantId': shop.tenantId, 'featureKey': 'stock', 'enabled': false, 'updatedAt': t.toIso8601String()},
          {'tenantId': shop.tenantId, 'featureKey': 'variants', 'enabled': true, 'updatedAt': t.toIso8601String()},
        ],
      }, cursor: '1'));

      await engine().syncNow();

      expect((await (db.select(db.customers)..where((x) => x.id.equals(customerId))).getSingle()).name, 'local');
      final flags = {for (final f in await db.select(db.tenantFeatureFlags).get()) f.featureKey: f.enabled};
      expect(flags, {'stock': false, 'variants': true});
    });

    test("this phone's devices row keeps the higher lastSeq; other phones are taken as pulled", () async {
      final mine = await (db.select(db.devices)..where((d) => d.id.equals(shop.deviceId))).getSingle();
      expect(mine.lastSeq, 1032);
      final t = DateTime.utc(2026, 11, 12);
      api.pages.add(page({
        'devices': [
          deviceWire(mine.copyWith(lastSeq: 900, updatedAt: t)),
          deviceWire(DeviceRow(id: 'phone-b', tenantId: shop.tenantId, code: 'B', lastSeq: 55, createdAt: t, updatedAt: t)),
        ],
      }, cursor: '1'));

      await engine().syncNow();

      final rows = {for (final d in await db.select(db.devices).get()) d.code: d.lastSeq};
      expect(rows, {'A': 1032, 'B': 55});
    });

    test('product serials take the server row; soft-deleted rows are kept with deletedAt', () async {
      final t = DateTime.utc(2026, 11, 12);
      final p = newProduct('phone', at: t);
      await addProduct(p);
      await engine().syncNow();
      api.pages.add(page({
        'productSerials': [
          serialWire(ProductSerialRow(
              id: 's1', tenantId: shop.tenantId, productId: p.id, serial: '356938035643809', status: SerialStatus.sold,
              saleLineId: 'line-on-phone-b', createdAt: t, updatedAt: t)),
        ],
        'products': [serverProduct(p.id, 'phone', t.add(const Duration(seconds: 1)))..['deletedAt'] = t.add(const Duration(seconds: 1)).toIso8601String()],
      }, cursor: '1'));

      await engine().syncNow();

      final s = await db.select(db.productSerials).getSingle();
      expect((s.status, s.saleLineId), (SerialStatus.sold, 'line-on-phone-b'));
      expect((await localProduct(p.id))!.deletedAt, isNotNull);
      expect(await c.read(productServiceProvider).products.watchById(p.id).first, isNull, reason: 'screens hide it');
    });

    test('product tint: ARGB locally, signed int32 on the wire (server column is int), and back', () async {
      const argb = 0xFFE0E7FF; // > int32 max
      final p = newProduct('tinted');
      await c.read(productServiceProvider).create(Product(
            id: p.id, tenantId: p.tenantId, name: p.name, cost: 1, price: 2, category: 'G', tint: argb, initial: 'T',
            createdAt: p.createdAt, updatedAt: p.updatedAt,
          ));
      final sent = SyncStore.rowsOf((await outbox(db)).single)[WireTable.products].single['tint'] as int;
      expect(sent, argb.toSigned(32));
      expect(sent, inInclusiveRange(-2147483648, 2147483647));
      await engine().syncNow();

      final later = p.updatedAt.add(const Duration(minutes: 1));
      api.pages.add(page({'products': [serverProduct(p.id, 'tinted', later)..['tint'] = argb.toSigned(32)]}, cursor: '1'));
      await engine().syncNow();
      expect((await localProduct(p.id))!.tint, argb);
    });

    test('the cursor is saved only after a whole page merged: a bad row rolls the page back', () async {
      final t = DateTime.utc(2026, 11, 12);
      final good = newId(), alsoGood = newId();
      api.pages
        ..add(page({'products': [serverProduct(good, 'page 1', t)]}, cursor: 'C1', hasMore: true))
        ..add(page({
          'products': [
            serverProduct(alsoGood, 'page 2, row 1', t),
            {'id': newId(), 'name': 'no price'}, // malformed: cost/price/updatedAt missing
          ],
        }, cursor: 'C2'));
      final e = engine();

      await e.syncNow();

      expect(await store.cursor(), 'C1');
      expect(await localProduct(good), isNotNull);
      expect(await localProduct(alsoGood), isNull, reason: 'nothing of the failed page is kept');
      expect(e.snapshot.lastError, isNotNull);
    });

    test('a network failure on page 2 keeps page 1 and its cursor; the next sync continues from it', () async {
      final t = DateTime.utc(2026, 11, 12);
      api.pages
        ..add(page({'products': [serverProduct(newId(), 'p1', t)]}, cursor: 'C1', hasMore: true))
        ..add(page({'products': [serverProduct(newId(), 'p2', t)]}, cursor: 'C2'));
      api.pullErrors[1] = const ApiError.network();
      final e = engine();

      await e.syncNow();
      expect(await store.cursor(), 'C1');

      await e.syncNow();
      expect(api.pullCursors, ['0', 'C1', 'C1']);
      expect(await store.cursor(), 'C2');
    });
  });

  // ================================================================ first sign-in (§5.4)

  group('first download', () {
    test('no push before the first full pull; progress is reported; the flag is set when hasMore is false', () async {
      await db.writeState(SyncStateKeys.initialSyncDone, 'false');
      await sale(); // e.g. a unit restored with the outbox
      final t = DateTime.utc(2026, 11, 12);
      api.pages
        ..add(page({'products': [serverProduct(newId(), 'a', t), serverProduct(newId(), 'b', t)]}, cursor: 'C1', hasMore: true))
        ..add(page({'products': [serverProduct(newId(), 'c', t)]}, cursor: 'C2'));
      final e = engine();
      final progress = <int?>[];
      final sub = e.changes.listen((s) => progress.add(s.downloadedRows));

      await e.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(api.pushes, isEmpty, reason: 'an empty phone never pushes on top of a shop it has not seen');
      expect(progress, containsAllInOrder([0, 2, 3]));
      expect(await store.initialSyncDone(), isTrue);
      expect(initialDone, 1);

      await e.syncNow();
      expect(api.pushes, hasLength(1), reason: 'after the download, the outbox goes up');
    });

    test('an interrupted first download is not marked done', () async {
      await db.writeState(SyncStateKeys.initialSyncDone, 'false');
      api.pages.add(page({}, cursor: 'C1', hasMore: true));
      api.pullErrors[1] = const ApiError.network();
      await engine().syncNow();
      expect(await store.initialSyncDone(), isFalse);
      expect(initialDone, 0);
    });
  });

  // ================================================================ review (§7)

  group('sync issues and rejected units', () {
    test('resolving an issue calls the server and updates the local row at once', () async {
      final t = DateTime.utc(2026, 11, 12);
      Map<String, dynamic> issue({DateTime? resolvedAt}) => {
            'id': 'issue-1', 'tenantId': shop.tenantId, 'kind': 'serialDoubleSold', 'entityTable': 'ProductSerials',
            'entityId': 's1', 'detail': 'sold twice', 'resolvedAt': resolvedAt?.toIso8601String(),
            'createdAt': t.toIso8601String(), 'updatedAt': (resolvedAt ?? t).toIso8601String(),
          };
      api.pages.add(page({'syncIssues': [issue()]}, cursor: '1'));
      final e = engine();
      await e.syncNow();
      expect(await store.watchOpenIssues().first, hasLength(1));

      api.resolveAnswer = (_) => issue(resolvedAt: t.add(const Duration(minutes: 3)));
      await e.resolveIssue('issue-1');

      expect(api.resolved, ['issue-1']);
      expect(await store.watchOpenIssues().first, isEmpty);
    });

    test('"ပြင်ပြီး ပြန်ပို့မယ်": edits the local row, rebuilds the unit under a new id, sets it pending', () async {
      final p = newProduct('x' * 130);
      await addProduct(p);
      api.outcome = (_) => UnitOutcome.rejected;
      await engine().syncNow();
      final rejected = (await outbox(db)).single;
      expect(rejected.status, OutboxStatus.rejected);

      await store.resend(rejected.seq, edits: {
        WireTable.products: {
          p.id: {'name': 'ဆပ်ပြာ'},
        },
      });

      final again = (await outbox(db)).single;
      expect(again.seq, rejected.seq, reason: 'keeps its place in the push order');
      expect(again.unitId, isNot(rejected.unitId), reason: 'the server answers the old id with rejected forever');
      expect((again.status, again.attempts, again.rejectReason), (OutboxStatus.pending, 0, null));
      final row = SyncStore.rowsOf(again)[WireTable.products].single as Map;
      expect(row['name'], 'ဆပ်ပြာ');
      expect(DateTime.parse(row['updatedAt'] as String).isAfter(p.updatedAt) || row['updatedAt'] == isoMs(p.updatedAt), isTrue);
      expect((await localProduct(p.id))!.name, 'ဆပ်ပြာ');

      api.outcome = (_) => UnitOutcome.applied;
      await engine().syncNow();
      expect(await outbox(db), isEmpty);
    });

    test('only whitelisted text columns can be edited', () async {
      await addProduct(newProduct('p'));
      api.outcome = (_) => UnitOutcome.rejected;
      await engine().syncNow();
      final o = (await outbox(db)).single;
      await expectLater(
        store.resend(o.seq, edits: {
          WireTable.products: {
            'id': {'price': '1'},
          },
        }),
        throwsArgumentError,
      );
      expect((await outbox(db)).single.status, OutboxStatus.rejected, reason: 'nothing changed');
    });
  });

  test('provider wiring: a committed unit schedules a push through the real UoW hook', () async {
    final (c2, _) = await driftContainer(db, store: shop.store, overrides: [syncApiProvider.overrideWithValue(api)]);
    addTearDown(c2.dispose);
    final e = c2.read(syncEngineProvider);
    expect(e.enabled, isTrue);
    await sell(c2, [water]);
    expect(api.pushes, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 2300)); // §5.1: 2 s after the commit
    for (var i = 0; i < 50 && api.pushes.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(api.pushes, hasLength(1));
  });
}
