// QA round 11 — 17180db (BUG-32), adversarial, on the real local database (Drift) and the real SyncEngine (fake HTTP).
//
// Owner (BUG-32 hand-over): "general rule: a pull never overwrites a row that is part of an unsent or blocked outbox
// unit, for any table (not only sales voids). Test: void fails to send, next pull must not undo it, day totals stay
// correct." Implementation: sync_store.dart mergePage skips rows whose "table:id" is in any outbox unit (pending or
// rejected), remembers them + the page's start cursor (syncState repullKeys / repullFrom) and rewinds the pull cursor
// once no unit holding them is left, so the server's current copy is pulled again.
//
// What the developer's m/pending_rows_pull_test.dart does not do, and this file does: every synced table in ONE unit
// (14 tables incl. tenants, tenantFeatures, devices, serials, ledgers, syncIssues); rejected → fixed → resent; several
// units over the same row (one applied, one blocked); a row the SERVER kept from another phone (last-writer-wins lost:
// the phone must converge to it); a row skipped on two different pages and in two cycles; an app restart (file
// database closed and reopened) between the skip and the send; the first download; the voidSale "skipped" outcome
// (the other phone voided first); no duplicates after the re-pull; and the dashboard, sales history, sale detail and
// report screens (not only the DB).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/core/widgets/money_text.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/reports/data/report_repository.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show drive, settle;

const _tid = 't-qa-r11';
final _t1 = DateTime.utc(2026, 11, 14, 9), _t2 = DateTime.utc(2030, 1, 1);
String _iso(DateTime t) => t.toIso8601String();
String _c(int n) => n.toRadixString(16).padLeft(16, '0');

Map<String, dynamic> _base(String id, DateTime at) => {
      'id': id, 'tenantId': _tid, 'createdAt': '2026-11-14T08:00:00.000Z', 'updatedAt': _iso(at), 'deletedAt': null,
    };

/// One row per synced table. [server] = the other copy (every nullable column NULL, texts changed, feature off).
Map<String, List<Map<String, dynamic>>> _rows(Map<String, String> id, DateTime at, {required bool server}) {
  T? v<T>(T value) => server ? null : value;
  String s(String local) => server ? '$local (server)' : local;
  return {
    'tenants': [
      {..._base(_tid, at), 'name': s('QA r11 shop'), 'templateId': 'phone', 'township': v('ဗဟန်း'), 'plan': v('free'),
        'planExpiresAt': v('2027-01-01T00:00:00.000Z')},
    ],
    'tenantFeatures': [
      {'tenantId': _tid, 'featureKey': 'stock', 'enabled': !server, 'updatedAt': _iso(at)},
    ],
    'devices': [
      {..._base(id['dev']!, at), 'code': 'B', 'name': v('ကောင်တာ ၂'), 'lastSeq': 7, 'lastSyncAt': v(_iso(_t1))},
    ],
    'products': [
      {..._base(id['p']!, at), 'name': s('QA r11 phone'), 'category': 'ဖုန်း', 'unit': 'လုံး', 'barcode': v('8850000011001'),
        'cost': 100, 'price': 150, 'wholesalePrice': v(140), 'lowAlertMilli': 0, 'warrantyMonths': v(6),
        'expiryAlertDays': v(30), 'tint': 0, 'initial': 'Q'},
    ],
    'productVariants': [
      {..._base(id['v']!, at), 'productId': id['p'], 'size': s('M'), 'color': 'အနီ'},
    ],
    'productBatches': [
      {..._base(id['b']!, at), 'productId': id['p'], 'batchNo': s('R11B'), 'expiryDate': v('2027-03-01')},
    ],
    'productSerials': [
      {..._base(id['s']!, at), 'productId': id['p'], 'serial': '359911000011001', 'status': server ? 'inStock' : 'sold',
        'saleLineId': v(id['l'])},
    ],
    'customers': [
      {..._base(id['c']!, at), 'name': s('QA r11 မမ'), 'phone': '09790011001', 'address': v('ရန်ကုန်'),
        'creditLimit': v(50000), 'note': v('VIP')},
    ],
    'sales': [
      {..._base(id['sale']!, at), 'no': 'A-0001', 'deviceId': v(id['dev']), 'method': 'cash', 'customerId': v(id['c']),
        'customerName': v('QA r11 မမ'), 'total': 150, 'voidedAt': v(_iso(_t1)), 'syncedAt': v(_iso(_t1))},
    ],
    'saleLines': [
      {..._base(id['l']!, at), 'saleId': id['sale'], 'productId': v(id['p']), 'variantId': v(id['v']),
        'batchId': v(id['b']), 'serialId': v(id['s']), 'name': s('QA r11 phone'), 'qtyMilli': 1000, 'price': 150,
        'costSnapshot': 100, 'lineTotal': 150},
    ],
    'payments': [
      {..._base(id['pay']!, at), 'saleId': id['sale'], 'method': 'cash', 'amount': 150, 'received': v(200)},
    ],
    'stockMovements': [
      {..._base(id['m']!, at), 'productId': id['p'], 'variantId': v(id['v']), 'batchId': v(id['b']), 'type': 'sale',
        'qtyMilli': -1000, 'saleId': v(id['sale']), 'note': s(''), 'deviceId': v(id['dev'])},
    ],
    'debtEntries': [
      {..._base(id['d']!, at), 'customerId': id['c'], 'type': 'adjustment', 'amount': 10, 'saleId': v(id['sale']),
        'saleNo': v('A-0001'), 'method': v('cash'), 'note': v('void'), 'deviceId': v(id['dev'])},
    ],
    'syncIssues': [
      {..._base(id['i']!, at), 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': id['p'], 'detail': 'x',
        'data': v('{"barcode":"8850000011001"}'), 'deviceId': v(id['dev']), 'resolvedAt': v(_iso(_t1))},
    ],
  };
}

Map<String, String> _ids() => {for (final k in ['dev', 'p', 'v', 'b', 's', 'c', 'sale', 'l', 'pay', 'm', 'd', 'i']) k: newId()};

/// A snapshot of every row of every table in [id] (raw SQLite values), to compare before / after.
Future<Map<String, Object?>> _snapshot(AppDatabase db, Map<String, String> id) async {
  Future<Map<String, Object?>> q(String table, String where, String key) async {
    final r = await db.customSelect('SELECT * FROM "$table" WHERE "$where" = ?', variables: [Variable.withString(key)])
        .getSingleOrNull();
    return {table: r?.data};
  }

  return {
    ...await q('tenants', 'id', _tid),
    ...await q(db.tenantFeatureFlags.actualTableName, 'featureKey', 'stock'),
    ...await q('devices', 'id', id['dev']!),
    ...await q('products', 'id', id['p']!),
    ...await q('productVariants', 'id', id['v']!),
    ...await q('productBatches', 'id', id['b']!),
    ...await q('productSerials', 'id', id['s']!),
    ...await q('customers', 'id', id['c']!),
    ...await q('sales', 'id', id['sale']!),
    ...await q('saleLines', 'id', id['l']!),
    ...await q('payments', 'id', id['pay']!),
    ...await q('stockMovements', 'id', id['m']!),
    ...await q('debtEntries', 'id', id['d']!),
    ...await q('syncIssues', 'id', id['i']!),
  };
}

Future<int> _outbox(AppDatabase db, Map<String, dynamic> rows, {String kind = 'upsertProduct'}) =>
    db.into(db.outbox).insert(OutboxCompanion.insert(
          unitId: newId(), kind: kind, rowsJson: jsonEncode(rows), clientTime: DateTime.now().millisecondsSinceEpoch));

Future<OutboxRow> _unit(AppDatabase db, int seq) => (db.select(db.outbox)..where((o) => o.seq.equals(seq))).getSingle();

UnitResult _r(OutboxRow o, UnitOutcome out) => UnitResult(unitId: o.unitId, outcome: out, code: 'invalid', reason: 'x');

Future<Set<String>?> _repullKeys(AppDatabase db) async {
  final raw = await db.readState(SyncStateKeys.repullKeys);
  return raw == null ? null : (jsonDecode(raw) as List).cast<String>().toSet();
}

Map<String, dynamic> _product(String id, String name, DateTime at, {String tenant = _tid}) => {
      ..._base(id, at), 'tenantId': tenant, 'name': name, 'category': 'x', 'unit': '', 'barcode': null, 'cost': 100,
      'price': 150, 'wholesalePrice': null, 'lowAlertMilli': 0, 'warrantyMonths': null, 'expiryAlertDays': null, 'tint': 0,
      'initial': 'Q',
    };

Future<String?> _name(AppDatabase db, String id) async =>
    (await (db.select(db.products)..where((x) => x.id.equals(id))).getSingleOrNull())?.name;

void main() {
  setUpAll(loadAppFonts);

  // ================================================================ TC-SYNC-NEW-20 every table, rejected → fixed → resent
  group('TC-SYNC-NEW-20 a pull never overwrites a row of an unsent or blocked unit, any table', () {
    test('ONE pending unit with a row of each of the 14 synced tables: a page with the server copies (changed texts, '
        'nullables NULL, feature off) changes none of them, a bystander row on the same page IS merged; after the unit '
        'is applied the cursor goes back to the page start and the re-pulled server copies are taken', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final id = _ids();
      final local = _rows(id, _t1, server: false);
      await store.mergePage(page(local, cursor: _c(1)));
      final seq = await _outbox(db, local);
      final before = await _snapshot(db, id);
      expect(before.values.where((v) => v == null), isEmpty, reason: 'setup: every row exists locally');

      final bystander = newId();
      final server = _rows(id, _t2, server: true)..['products'] = [..._rows(id, _t2, server: true)['products']!,
          _product(bystander, 'QA r11 bystander', _t2)];
      final merged = await store.mergePage(page(server, cursor: _c(2)));
      final after = await _snapshot(db, id);
      expect({for (final k in before.keys) if (jsonEncode(before[k]) != jsonEncode(after[k])) k: after[k]}, isEmpty,
          reason: 'no row of the pending unit may change, on any table');
      expect(merged, 1, reason: 'only the bystander was merged');
      expect(await _name(db, bystander), 'QA r11 bystander');
      expect(await _repullKeys(db), {
        'tenants:$_tid', 'tenantFeatures:stock', 'devices:${id['dev']}', 'products:${id['p']}', 'productVariants:${id['v']}',
        'productBatches:${id['b']}', 'productSerials:${id['s']}', 'customers:${id['c']}', 'sales:${id['sale']}',
        'saleLines:${id['l']}', 'payments:${id['pay']}', 'stockMovements:${id['m']}', 'debtEntries:${id['d']}',
        'syncIssues:${id['i']}',
      });
      expect(await db.readState(SyncStateKeys.repullFrom), _c(1));
      expect(await store.cursor(), _c(2));

      await store.applyResults([await _unit(db, seq)], [_r(await _unit(db, seq), UnitOutcome.applied)]);
      expect(await store.cursor(), _c(1), reason: 'pull again from before the skipped page');
      expect(await _repullKeys(db), isNull);
      await store.mergePage(page(_rows(id, _t2, server: true), cursor: _c(3)));
      final taken = await _snapshot(db, id);
      expect({for (final k in before.keys) if (jsonEncode(before[k]) == jsonEncode(taken[k])) k}, isEmpty,
          reason: 'every row now has the server copy');
      expect((await db.select(db.products).get()).length, 2, reason: 'no duplicate rows after the re-pull');
    });

    test('rejected (blocked) → protected; another unit applied meanwhile does not rewind; fixed with "ပြန်ပို့မယ်" '
        '(resend, still protected while pending) → applied → rewind to the EARLIEST skipped page; re-pull takes the server copy',
        () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final p = newId(), other = newId();
      await store.mergePage(page({'products': [_product(p, 'QA r11 soap', _t1), _product(other, 'QA r11 other', _t1)]},
          cursor: _c(1)));
      final seq = await _outbox(db, {'products': [_product(p, 'x' * 200, _t1)]});
      await store.applyResults([await _unit(db, seq)], [_r(await _unit(db, seq), UnitOutcome.rejected)]);
      final otherSeq = await _outbox(db, {'products': [_product(other, 'QA r11 other 2', _t1)]});

      await store.mergePage(page({'products': [_product(p, 'server A', _t2)]}, cursor: _c(2)));
      expect(await _name(db, p), 'QA r11 soap', reason: 'blocked unit: protected');
      await store.applyResults([await _unit(db, otherSeq)], [_r(await _unit(db, otherSeq), UnitOutcome.applied)]);
      expect(await store.cursor(), _c(2), reason: 'the blocked unit still holds the row: no rewind');

      await store.resend(seq, edits: {'products': {p: {'name': 'QA r11 soap fixed'}}});
      expect((await _unit(db, seq)).status, OutboxStatus.pending);
      await store.mergePage(page({'products': [_product(p, 'server B', _t2)]}, cursor: _c(3)));
      expect(await _name(db, p), 'QA r11 soap fixed', reason: 'resent unit pending again: still protected');
      expect(await db.readState(SyncStateKeys.repullFrom), _c(1), reason: 'the earliest page start is kept');

      await store.applyResults([await _unit(db, seq)], [_r(await _unit(db, seq), UnitOutcome.applied)]);
      expect(await store.cursor(), _c(1));
      await store.mergePage(page({'products': [_product(p, 'QA r11 soap fixed', _t2)]}, cursor: _c(4)));
      expect(await _name(db, p), 'QA r11 soap fixed');
      expect(await _repullKeys(db), isNull);
    });
  });

  // ================================================================ TC-SYNC-NEW-21 several units, LWW lost, two pages
  group('TC-SYNC-NEW-21 several units over one row; the server kept the other phone\'s copy; a row skipped on two pages',
      () {
    test('two units over the same product: the first applied, the second rejected → no rewind; the second fixed and '
        'sent → rewind', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final p = newId();
      await store.mergePage(page({'products': [_product(p, 'v0', _t1)]}, cursor: _c(1)));
      final s1 = await _outbox(db, {'products': [_product(p, 'edit 1', _t1)]});
      final s2 = await _outbox(db, {'products': [_product(p, 'edit 2', _t1)]});
      await db.customUpdate('UPDATE products SET name = ? WHERE id = ?',
          variables: [Variable.withString('edit 2'), Variable.withString(p)]);
      await store.mergePage(page({'products': [_product(p, 'server', _t2)]}, cursor: _c(2)));
      expect(await _name(db, p), 'edit 2');
      final blocked = await store.applyResults([await _unit(db, s1), await _unit(db, s2)],
          [_r(await _unit(db, s1), UnitOutcome.applied), _r(await _unit(db, s2), UnitOutcome.rejected)]);
      expect(blocked, isTrue);
      expect(await store.cursor(), _c(2), reason: 'unit 2 still holds it: no rewind');
      expect(await _repullKeys(db), {'products:$p'});
      await store.resend(s2);
      await store.applyResults([await _unit(db, s2)], [_r(await _unit(db, s2), UnitOutcome.applied)]);
      expect(await store.cursor(), _c(1));
      expect(await _repullKeys(db), isNull);
    });

    test('engine: A edits a product offline (older), B\'s newer edit reaches the server first; A\'s pull skips B\'s copy; '
        'A\'s push is applied but the server keeps B\'s (last-writer-wins) → A pulls again from before that page and ends '
        'with B\'s copy (the server never sends it again otherwise)', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final (c, shop) = await driftContainer(db, seed: false);
      addTearDown(c.dispose);
      final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
      await store.markInitialSyncDone();
      final api = FakeSyncApi();
      final now = DateTime.utc(2026, 11, 14, 12);
      final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => now);
      addTearDown(engine.dispose);
      final t = DateTime.utc(2026, 11, 14, 8);
      final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r11 oil', cost: 100, price: 150, category: 'x',
          tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
      await c.read(productServiceProvider).create(p);
      api.pages.add(page({}, cursor: _c(5)));
      await engine.syncNow(manual: true);
      expect(await db.select(db.outbox).get(), isEmpty);
      expect(await store.cursor(), _c(5));

      await c.read(productServiceProvider).update(p.copyWith(name: 'QA r11 oil (A)', updatedAt: DateTime.utc(2026, 11, 14, 9)));
      api.pushErrors.add(const ApiError.network());
      await engine.syncNow(); // A's push fails → back-off
      final aRow = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
      final bCopy = {...productWire(aRow), 'name': 'QA r11 oil (B)', // B edited one minute after A
        'updatedAt': aRow.updatedAt.toUtc().add(const Duration(minutes: 1)).toIso8601String()};
      api.pages.add(page({'products': [bCopy]}, cursor: _c(9)));
      await engine.syncNow(); // within the back-off: pull only → B's copy skipped
      expect(await _name(db, p.id), 'QA r11 oil (A)');

      api.pages.add(page({'products': [bCopy]}, cursor: _c(9))); // the server's current copy (B's: it won)
      await engine.syncNow(manual: true);
      expect(api.pullCursors.last, _c(5), reason: 'pulled again from before the skipped page');
      expect(await _name(db, p.id), 'QA r11 oil (B)', reason: 'A converges to the copy the server kept');
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('one row skipped on two pages of one pull (hasMore) and again in a later cycle: repullFrom stays the earliest '
        'start; one rewind after the send; nothing duplicated', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final api = FakeSyncApi();
      final now = DateTime.utc(2026, 11, 14, 12);
      final engine = SyncEngine(api: api, store: store, deviceId: 'phone-a', clock: () => now);
      addTearDown(engine.dispose);
      await store.markInitialSyncDone();
      final p = newId(), q = newId();
      api.pages.add(page({'products': [_product(p, 'v0', _t1)]}, cursor: _c(5)));
      await engine.syncNow(manual: true);
      await _outbox(db, {'products': [_product(p, 'local edit', _t1)]});
      await db.customUpdate('UPDATE products SET name = ? WHERE id = ?',
          variables: [Variable.withString('local edit'), Variable.withString(p)]);
      api.pushErrors.add(const ApiError.network());
      await engine.syncNow(); // push fails
      api.pages
        ..add(page({'products': [_product(p, 'server 1', _t2)]}, cursor: _c(10), hasMore: true))
        ..add(page({'products': [_product(p, 'server 2', _t2), _product(q, 'QA r11 bystander', _t1)]}, cursor: _c(20)));
      await engine.syncNow(); // pull only: two pages
      api.pages.add(page({'products': [_product(p, 'server 3', _t2)]}, cursor: _c(30)));
      await engine.syncNow(); // another cycle, pull only
      expect((await _name(db, p), await _name(db, q)), ('local edit', 'QA r11 bystander'));
      expect((await db.readState(SyncStateKeys.repullFrom), await store.cursor()), (_c(5), _c(30)));

      api.pages.add(page({'products': [_product(p, 'server 3', _t2), _product(q, 'QA r11 bystander', _t1)]}, cursor: _c(31)));
      await engine.syncNow(manual: true);
      expect(api.pullCursors.last, _c(5));
      expect((await _name(db, p), (await db.select(db.products).get()).length), ('server 3', 2));
      expect(await _repullKeys(db), isNull);
      api.pages.add(page({}, cursor: _c(31)));
      await engine.syncNow(manual: true);
      expect(api.pullCursors.last, _c(31), reason: 'only ONE rewind');
    });
  });

  // ================================================================ TC-SYNC-NEW-22 app restart, first download
  group('TC-SYNC-NEW-22 restart between skip and send; the first download', () {
    test('file database: skip, close the app (database closed), reopen with a new engine → the skipped row is still '
        'protected and the rewind happens after the send', () async {
      final dir = Directory.systemTemp.createTempSync('qa_r11_restart');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/zaypos.sqlite');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final now = DateTime.utc(2026, 11, 14, 12);
      final p = newId();

      var db = AppDatabase(NativeDatabase(file));
      var store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      var api = FakeSyncApi();
      var engine = SyncEngine(api: api, store: store, deviceId: 'phone-a', clock: () => now);
      await store.markInitialSyncDone();
      api.pages.add(page({'products': [_product(p, 'v0', _t1)]}, cursor: _c(5)));
      await engine.syncNow(manual: true);
      await _outbox(db, {'products': [_product(p, 'local edit', _t1)]});
      await db.customUpdate('UPDATE products SET name = ? WHERE id = ?',
          variables: [Variable.withString('local edit'), Variable.withString(p)]);
      api.pushErrors.add(const ApiError.network());
      await engine.syncNow();
      api.pages.add(page({'products': [_product(p, 'server', _t2)]}, cursor: _c(9)));
      await engine.syncNow();
      expect(await _name(db, p), 'local edit');
      engine.dispose();
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      expect((await store.cursor(), await db.readState(SyncStateKeys.repullFrom)), (_c(9), _c(5)),
          reason: 'remembered across the restart');
      expect(await _repullKeys(db), {'products:$p'});
      api = FakeSyncApi();
      engine = SyncEngine(api: api, store: store, deviceId: 'phone-a', clock: () => now);
      addTearDown(engine.dispose);
      api.pages.add(page({'products': [_product(p, 'server', _t2)]}, cursor: _c(9)));
      await engine.syncNow();
      expect(api.pushes, hasLength(1));
      expect(api.pullCursors, [_c(5)]);
      expect(await _name(db, p), 'server');
    });

    test('first download with a unit recorded before it finished: the row is skipped, the push after the download '
        'rewinds to "0", the next cycle downloads again and takes the server copy; no duplicates; the app opens once',
        () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final api = FakeSyncApi();
      var opened = 0;
      final engine = SyncEngine(api: api, store: store, deviceId: 'phone-a', onInitialSyncDone: () => opened++);
      addTearDown(engine.dispose);
      final p = newId(), q = newId();
      await store.mergePage(page({'products': [_product(p, 'local', _t1)]}, cursor: '0')); // recorded locally
      await _outbox(db, {'products': [_product(p, 'local', _t1)]});
      final full = page({'products': [_product(p, 'server', _t2), _product(q, 'QA r11 other', _t2)]}, cursor: _c(40));
      api.pages.add(full);
      await engine.syncNow(manual: true);
      expect((opened, await store.initialSyncDone()), (1, true));
      expect(api.pushes, hasLength(1), reason: 'the unit is sent after the download');
      expect(await _name(db, p), 'local', reason: 'not overwritten during the first download');
      expect(await store.cursor(), '0', reason: 'rewound to the start of the skipped page');
      api.pages.add(full);
      await engine.syncNow(manual: true);
      expect(api.pullCursors, ['0', '0']);
      expect((await _name(db, p), (await db.select(db.products).get()).length, opened), ('server', 2, 1));
    });
  });

  // ================================================================ TC-SYNC-NEW-23 voidSale "skipped"
  test('TC-SYNC-NEW-23 the other phone voided the sale first: A\'s void is pending, the pull brings B\'s voided sale '
      '(skipped) and B\'s stock return; A\'s push answer is "skipped" → A\'s own return rows dropped, rewind, re-pull → '
      'A matches the server: B\'s voidedAt, ONE stock return, stock 5, today\'s sales 0', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final api = FakeSyncApi();
    final now = DateTime.now().toUtc();
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => now);
    addTearDown(engine.dispose);
    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r11 tea', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(2), price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    api.pages.add(page({}, cursor: _c(10)));
    await engine.syncNow(manual: true);
    Future<int> stock() async => (await (db.select(db.stockMovements)..where((m) => m.productId.equals(p.id))).get())
        .fold<int>(0, (a, m) => a + m.qtyMilli);
    Future<int> todaySales() async =>
        (await c.read(reportRepositoryProvider).watchReport(ReportPeriod.today).first).summary.sales;
    expect((await stock(), await todaySales()), (Qty.units(3), 300));

    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    final mine = (await (db.select(db.stockMovements)..where((m) => m.saleId.equals(sale.id) & m.qtyMilli.isBiggerThanValue(0)))
        .get()).single;
    api.pushErrors.add(const ApiError.network());
    await engine.syncNow();
    final bVoidedAt = DateTime.utc(2026, 11, 14, 1).toIso8601String();
    final serverSale = {...saleWire(await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle()),
      'voidedAt': bVoidedAt, 'deviceId': 'phone-b'};
    final bReturn = {...movementWire(mine), 'id': newId(), 'deviceId': 'phone-b'};
    final serverPage = page({'sales': [serverSale], 'stockMovements': [bReturn]}, cursor: _c(20));
    api.pages.add(serverPage);
    await engine.syncNow(); // pull only
    final during = await stock();
    // ignore: avoid_print
    print('TC-SYNC-NEW-23 stock while A\'s void is pending and B\'s return is pulled: ${Qty.format(during)} (true: 5)');
    expect((await todaySales()), 0, reason: 'voided on A, not undone by the pull');

    api.outcome = (u) => u.kind == 'voidSale' ? UnitOutcome.skipped : UnitOutcome.applied;
    api.pages.add(serverPage);
    await engine.syncNow(manual: true);
    expect(api.pullCursors.last, _c(10), reason: 'pulled again from before the skipped page');
    final row = await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle();
    expect(row.voidedAt?.toUtc().toIso8601String(), bVoidedAt, reason: 'the server\'s copy (B\'s void)');
    final moves = await (db.select(db.stockMovements)..where((m) => m.productId.equals(p.id))).get();
    expect((moves.length, await stock(), await todaySales()), (3, Qty.units(5), 0),
        reason: 'restock, sale, ONE return (B\'s); A\'s own return dropped');
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  // ================================================================ TC-SYNC-NEW-24 the screens
  testWidgets('TC-SYNC-NEW-24 screens while the void is unsent and a pull brings the unvoided sale, and after the send: '
      'with one other (valid) sale of 150: dashboard "ဒီနေ့ ရောင်းရငွေ" 150 Ks / 1 ကြိမ်, sales history 150 Ks, sale detail '
      '"ပယ်ဖျက်ပြီး" (not "ပယ်ဖျက်မယ်"), report 150 Ks', (tester) async {
    final db = memoryDb();
    addTearDown(() => tester.runAsync(db.close));
    final api = FakeSyncApi()..pullErrors[0] = const ApiError.network();
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);

    final t = nowUtc();
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r11 coffee', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await drive(tester, () => c.read(productServiceProvider).create(p, initialStock: [
          restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
        ]));
    final sale = await drive(tester, () => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(2), price: 150,
            cost: 100),
        ], method: PaymentMethod.cash)));
    // a second sale (1 × 150) that stays valid: the totals must be exactly 150 / 1 sale
    await drive(tester, () => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: Qty.units(1), price: 150,
            cost: 100),
        ], method: PaymentMethod.cash)));
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true)); // applied; the pull fails
    final echo = jsonDecode(jsonEncode(saleWire((await tester.runAsync(
        () => (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle()))!))) as Map<String, dynamic>;

    for (var i = 0; i < 50; i++) {
      api.pushErrors.add(const ApiError.network());
    }
    await drive(tester, () => c.read(voidSaleServiceProvider).setVoided(sale.id, true));
    await drive(tester, () => c.read(syncEngineProvider).syncNow()); // push fails
    api.pages.add(page({'sales': [echo]}, cursor: _c(10)));
    await drive(tester, () => c.read(syncEngineProvider).syncNow()); // within the back-off: pull only
    expect(api.pullCursors.length, greaterThanOrEqualTo(2), reason: 'the pull with the unvoided sale ran');
    expect((await tester.runAsync(() => db.select(db.outbox).get()))!.map((o) => o.kind), contains('voidSale'));

    Future<Map<String, Object>> screens() async {
      final r = c.read(appRouterProvider);
      r.go(Routes.dashboard);
      await settle(tester);
      final dash = tester.widget<MoneyText>(find.byType(MoneyText).first).amount;
      final dashCount = find.text('1 ကြိမ်').evaluate().isNotEmpty;
      r.go(Routes.sales);
      await settle(tester);
      final hist = tester.widget<MoneyText>(find.byType(MoneyText).first).amount;
      r.go(Routes.sale(sale.id));
      await settle(tester);
      final badge = find.text('ပယ်ဖျက်ပြီး').evaluate().isNotEmpty;
      final voidAgain = find.text('ပယ်ဖျက်မယ်').evaluate().isNotEmpty;
      r.go(Routes.reports);
      await settle(tester);
      final report = tester.widget<MoneyText>(find.byType(MoneyText).first).amount;
      return {'dashboard': dash, 'dashboard 1 ကြိမ်': dashCount, 'history': hist, 'badge ပယ်ဖျက်ပြီး': badge,
        'offers ပယ်ဖျက်မယ်': voidAgain, 'report': report};
    }

    const expected = {'dashboard': 150, 'dashboard 1 ကြိမ်': true, 'history': 150, 'badge ပယ်ဖျက်ပြီး': true,
      'offers ပယ်ဖျက်မယ်': false, 'report': 150};
    expect(await screens(), expected, reason: 'void unsent, the pull brought voidedAt NULL');

    api.pushErrors.clear();
    final voidedAt = nowUtc().toIso8601String();
    api.pages.add(page({'sales': [{...echo, 'voidedAt': voidedAt, 'updatedAt': voidedAt}]}, cursor: _c(11)));
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    expect((await tester.runAsync(() => db.select(db.outbox).get()))!, isEmpty);
    expect(await screens(), expected, reason: 'after the send and the re-pull');
    expect((await tester.runAsync(() => db.select(db.sales).get()))!.length, 2, reason: 'no duplicate sale');
  });
}
