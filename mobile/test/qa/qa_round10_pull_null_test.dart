// QA round 10 — 8b513b5 (BUG-31), adversarial, on the real local database (in-memory Drift + SyncStore.mergePage).
//
// Owner, 2026-11-14 (hand-over): "when applying pulled rows, a null/empty value from the server must overwrite the local
// value (full-row apply under the existing LWW and pending-outbox rules, not 'skip empty fields'). Check both directions:
// the server pull response must include null fields (not omitted by JSON settings); a cleared field on push is sent as
// null and the server stores null."
// phase3-sync.md §5.3: ledgers + syncIssues "insert or replace by id (server is truth; local copies are identical)";
// "sales.voidedAt: take the server value"; products, productVariants, productBatches, customers, tenantFeatures, tenants
// "replace only if pulled.updatedAt >= local.updatedAt and no pending outbox unit contains that id"; productSerials "take
// the server row"; own devices row "lastSeq = max(local, pulled)".
//
// What the developer's m/pull_null_test.dart does not do, and this file does: EVERY synced table with a nullable column
// (incl. warrantyMonths, batches.expiryDate, serials.saleLineId, sales.customerId/voidedAt, devices.name,
// tenants.township/plan, issues.resolvedAt, deletedAt = restore), equal timestamps, older rows on every LWW table, an
// unpushed customer, the own device row, the real edit form (all four fields incl. "သက်တမ်း မမှတ်ပါ" and warranty
// "မရှိ"), and an unpushed void (a ledger row that is NOT identical to the server's yet).
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import '../sync_screens_test.dart' show drive, settle;
import 'qa_form_helpers.dart';

const _tid = 't-qa-r10';
final _t1 = DateTime.utc(2026, 11, 14, 9), _t2 = DateTime.utc(2026, 11, 14, 10);
String _iso(DateTime t) => t.toIso8601String();

Map<String, dynamic> _base(String id, DateTime at, {DateTime? deletedAt}) => {
      'id': id, 'tenantId': _tid, 'createdAt': '2026-11-14T08:00:00.000Z', 'updatedAt': _iso(at),
      'deletedAt': deletedAt == null ? null : _iso(deletedAt),
    };

/// Every synced table, one row each; [full] = every nullable column set, otherwise every nullable column null
/// (and deletedAt null = restored).
Map<String, List<Map<String, dynamic>>> _rows(Map<String, String> id, DateTime at, {required bool full}) {
  T? v<T>(T value) => full ? value : null;
  final del = full ? DateTime.utc(2026, 11, 14, 8, 30) : null;
  return {
    'tenants': [
      {..._base(_tid, at), 'name': 'QA r10 shop', 'templateId': 'phone', 'township': v('ဗဟန်း'), 'plan': v('free'),
        'planExpiresAt': v('2027-01-01T00:00:00.000Z')},
    ],
    'devices': [
      {..._base(id['dev']!, at), 'code': 'B', 'name': v('ကောင်တာ ၂'), 'lastSeq': 7, 'lastSyncAt': v(_iso(_t1))},
    ],
    'products': [
      {..._base(id['p']!, at, deletedAt: del), 'name': 'QA r10 phone', 'category': 'ဖုန်း', 'unit': 'လုံး',
        'barcode': v('8850000010001'), 'cost': 100, 'price': 150, 'wholesalePrice': v(140), 'lowAlertMilli': 0,
        'warrantyMonths': v(6), 'expiryAlertDays': v(30), 'tint': 0, 'initial': 'Q'},
    ],
    'productVariants': [
      {..._base(id['v']!, at, deletedAt: del), 'productId': id['p'], 'size': 'M', 'color': 'အနီ'},
    ],
    'productBatches': [
      {..._base(id['b']!, at), 'productId': id['p'], 'batchNo': 'R10B', 'expiryDate': v('2027-03-01')},
    ],
    'productSerials': [
      {..._base(id['s']!, at), 'productId': id['p'], 'serial': '359910000010001', 'status': full ? 'sold' : 'inStock',
        'saleLineId': v(id['l'])},
    ],
    'customers': [
      {..._base(id['c']!, at), 'name': 'QA r10 မမ', 'phone': '09790010001', 'address': v('ရန်ကုန်'),
        'creditLimit': v(50000), 'note': v('VIP')},
    ],
    'sales': [
      {..._base(id['sale']!, at), 'no': 'A-0001', 'deviceId': v(id['dev']), 'method': 'cash', 'customerId': v(id['c']),
        'customerName': v('QA r10 မမ'), 'total': 150, 'voidedAt': v(_iso(_t1)), 'syncedAt': v(_iso(_t1))},
    ],
    'saleLines': [
      {..._base(id['l']!, at), 'saleId': id['sale'], 'productId': v(id['p']), 'variantId': v(id['v']),
        'batchId': v(id['b']), 'serialId': v(id['s']), 'name': 'QA r10 phone', 'qtyMilli': 1000, 'price': 150,
        'costSnapshot': 100, 'lineTotal': 150},
    ],
    'payments': [
      {..._base(id['pay']!, at), 'saleId': id['sale'], 'method': 'cash', 'amount': 150, 'received': v(200)},
    ],
    'stockMovements': [
      {..._base(id['m']!, at), 'productId': id['p'], 'variantId': v(id['v']), 'batchId': v(id['b']), 'type': 'sale',
        'qtyMilli': -1000, 'saleId': v(id['sale']), 'note': '', 'deviceId': v(id['dev'])},
    ],
    'debtEntries': [
      {..._base(id['d']!, at), 'customerId': id['c'], 'type': 'adjustment', 'amount': 10, 'saleId': v(id['sale']),
        'saleNo': v('A-0001'), 'method': v('cash'), 'note': v('void'), 'deviceId': v(id['dev'])},
    ],
    'syncIssues': [
      {..._base(id['i']!, at), 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': id['p'], 'detail': 'x',
        'data': v('{"barcode":"8850000010001"}'), 'deviceId': v(id['dev']), 'resolvedAt': v(_iso(_t1))},
    ],
  };
}

/// The nullable columns of every table as stored in SQLite (raw, so nothing is hidden by a converter).
Future<Map<String, Object?>> _nullables(AppDatabase db, Map<String, String> id) async {
  Future<Map<String, Object?>> q(String table, String key, List<String> cols) async {
    final r = await db.customSelect('SELECT ${cols.map((c) => '"$c"').join(', ')} FROM "$table" WHERE "id" = ?',
        variables: [Variable.withString(key)]).getSingle();
    return {for (final c in cols) '$table.$c': r.data[c]};
  }

  return {
    ...await q('tenants', _tid, ['township', 'plan', 'planExpiresAt']),
    ...await q('devices', id['dev']!, ['name', 'lastSyncAt']),
    ...await q('products', id['p']!, ['barcode', 'wholesalePrice', 'warrantyMonths', 'expiryAlertDays', 'deletedAt']),
    ...await q('productVariants', id['v']!, ['deletedAt']),
    ...await q('productBatches', id['b']!, ['expiryDate']),
    ...await q('productSerials', id['s']!, ['saleLineId']),
    ...await q('customers', id['c']!, ['address', 'creditLimit', 'note']),
    ...await q('sales', id['sale']!, ['deviceId', 'customerId', 'customerName', 'voidedAt', 'syncedAt']),
    ...await q('saleLines', id['l']!, ['productId', 'variantId', 'batchId', 'serialId']),
    ...await q('payments', id['pay']!, ['received']),
    ...await q('stockMovements', id['m']!, ['variantId', 'batchId', 'saleId', 'deviceId']),
    ...await q('debtEntries', id['d']!, ['saleId', 'saleNo', 'method', 'note', 'deviceId']),
    ...await q('syncIssues', id['i']!, ['data', 'deviceId', 'resolvedAt']),
  };
}

Map<String, String> _ids() => {for (final k in ['dev', 'p', 'v', 'b', 's', 'c', 'sale', 'l', 'pay', 'm', 'd', 'i']) k: newId()};

void main() {
  setUpAll(loadAppFonts);

  group('TC-SYNC-NEW-16 pulled NULLs on every synced table', () {
    test('a newer row (ledgers: the server row) with every nullable column NULL clears all of them here; deletedAt NULL '
        '= the product / variant is live again', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final id = _ids();
      await store.mergePage(page(_rows(id, _t1, full: true), cursor: '01'));
      final before = await _nullables(db, id);
      expect(before.entries.where((e) => e.value == null).map((e) => e.key), isEmpty,
          reason: 'setup: every nullable column has a value');

      await store.mergePage(page(_rows(id, _t2, full: false), cursor: '02'));
      final after = await _nullables(db, id);
      expect({for (final e in after.entries) if (e.value != null) e.key: e.value}, isEmpty,
          reason: 'every column cleared on the server must be cleared on this phone');
      final serial = await db.select(db.productSerials).getSingle();
      expect(serial.status.name, 'inStock');
    });

    test('EQUAL updatedAt (spec: pulled >= local) on the LWW tables: the pulled NULLs are taken', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final id = _ids();
      await store.mergePage(page(_rows(id, _t1, full: true), cursor: '01'));
      final lww = _rows(id, _t1, full: false)..removeWhere((k, _) => !const {'tenants', 'products', 'productBatches',
          'customers'}.contains(k));
      await store.mergePage(page(lww, cursor: '02'));
      final after = await _nullables(db, id);
      expect({
        for (final k in ['tenants.township', 'tenants.plan', 'products.barcode', 'products.wholesalePrice',
          'products.warrantyMonths', 'products.expiryAlertDays', 'products.deletedAt', 'productBatches.expiryDate',
          'customers.address', 'customers.creditLimit', 'customers.note'])
          if (after[k] != null) k: after[k],
      }, isEmpty);
    });

    test('an OLDER row with NULLs clears nothing on any LWW table (products, variants, batches, customers, tenants)',
        () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      final id = _ids();
      await store.mergePage(page(_rows(id, _t2, full: true), cursor: '01'));
      final lww = _rows(id, _t1, full: false)..removeWhere((k, _) => !const {'tenants', 'products', 'productVariants',
          'productBatches', 'customers'}.contains(k));
      await store.mergePage(page(lww, cursor: '02'));
      final after = await _nullables(db, id);
      expect({
        for (final k in ['tenants.township', 'tenants.plan', 'tenants.planExpiresAt', 'products.barcode',
          'products.wholesalePrice', 'products.warrantyMonths', 'products.expiryAlertDays', 'products.deletedAt',
          'productVariants.deletedAt', 'productBatches.expiryDate', 'customers.address', 'customers.creditLimit',
          'customers.note'])
          if (after[k] == null) k,
      }, isEmpty, reason: 'last-writer-wins: an older row must not clear newer local values');
    });

    test('own device row: name / lastSyncAt NULL are taken, lastSeq never moves back', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final store = SyncStore(db, tenantId: _tid, deviceId: 'phone-a');
      Map<String, dynamic> dev(int seq, {String? name}) =>
          {..._base('phone-a', _t1), 'code': 'A', 'name': name, 'lastSeq': seq, 'lastSyncAt': name == null ? null : _iso(_t1)};
      await store.mergePage(page({'devices': [dev(40, name: 'ကောင်တာ')]}, cursor: '01'));
      await store.mergePage(page({'devices': [dev(12)]}, cursor: '02'));
      final r = await db.select(db.devices).getSingle();
      expect((r.name, r.lastSyncAt, r.lastSeq), (null, null, 40));
    });

    test('an UNPUSHED customer (pending upsertCustomer unit) is not touched by a newer pulled row with NULLs', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final (c, shop) = await driftContainer(db, seed: false);
      addTearDown(c.dispose);
      final t = DateTime.utc(2026, 11, 14, 8);
      final cu = Customer(id: newId(), tenantId: shop.tenantId, name: 'QA r10 ကိုကို', phone: '09790010002',
          address: 'မန္တလေး', creditLimit: 30000, note: 'x', createdAt: t, updatedAt: t);
      await c.read(customerServiceProvider).create(cu);
      expect((await db.select(db.outbox).get()).map((o) => o.kind), contains('upsertCustomer'));
      await SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).mergePage(page({
        'customers': [
          {..._base(cu.id, DateTime.utc(2030)), 'tenantId': shop.tenantId, 'name': 'server', 'phone': '09790010002',
            'address': null, 'creditLimit': null, 'note': null},
        ],
      }, cursor: '01'));
      final r = await (db.select(db.customers)..where((x) => x.id.equals(cu.id))).getSingle();
      expect((r.name, r.address, r.creditLimit, r.note), ('QA r10 ကိုကို', 'မန္တလေး', 30000, 'x'));
    });
  });

  // ================================================================ TC-SYNC-NEW-17 the pull and an unpushed void
  test('TC-SYNC-NEW-17 a sale voided on this phone, void not pushed yet; a pull brings the server copy of the sale '
      '(voidedAt NULL, e.g. the echo of its checkout): the sale must stay voided here until the void is pushed', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r10 soap', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    final echo = saleWire(await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle());
    await db.delete(db.outbox).go(); // product + checkout pushed and applied
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true); // offline: the voidSale unit is pending
    expect((await db.select(db.outbox).get()).map((o) => o.kind), ['voidSale']);

    await SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId)
        .mergePage(page({'sales': [jsonDecode(jsonEncode(echo)) as Map<String, dynamic>]}, cursor: '01'));
    final row = await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle();
    final stock = (await (db.select(db.stockMovements)..where((m) => m.productId.equals(p.id))).get())
        .fold(0, (a, m) => a + m.qtyMilli);
    expect(row.voidedAt, isNotNull,
        reason: 'the void is still in the outbox (local copy is NOT identical to the server\'s yet); stock here is '
            '${Qty.format(stock)} (the void already returned the item) while the sale shows as not voided');
  });

  test('TC-SYNC-NEW-17 the same through the real SyncEngine on a flaky network: checkout pushed, the pull drops; the '
      'cashier voids; the void push fails (back-off); the next automatic cycle skips the push and pulls → the sale must '
      'stay voided', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final api = FakeSyncApi()..pullErrors[0] = const ApiError.network();
    final now = DateTime.utc(2026, 11, 14, 12);
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => now);
    final t = DateTime.utc(2026, 11, 14, 8);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r10 tea', cost: 100, price: 150, category: 'x',
        tint: 0, initial: 'Q', createdAt: t, updatedAt: t);
    await c.read(productServiceProvider).create(p, initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(5)),
    ]);
    final sale = await c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
      (productId: p.id, variantId: null, batchId: null, serialId: null, name: p.name, qtyMilli: 1000, price: 150, cost: 100),
    ], method: PaymentMethod.cash));
    final echo = jsonDecode(jsonEncode(saleWire(await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle())))
        as Map<String, dynamic>;

    await engine.syncNow(manual: true); // push applied; the pull fails
    expect(await db.select(db.outbox).get(), isEmpty);
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    api.pushErrors.add(const ApiError.network());
    await engine.syncNow(); // void push fails → back-off
    api.pages.add(page({'sales': [echo]}, cursor: '10'));
    await engine.syncNow(); // automatic, within the back-off: no push, pull runs
    expect(api.pullCursors, hasLength(2), reason: 'the 2nd pull ran');
    expect((await db.select(db.outbox).get()).map((o) => o.kind), ['voidSale'], reason: 'the void is still pending');
    final row = await (db.select(db.sales)..where((s) => s.id.equals(sale.id))).getSingle();
    expect(row.voidedAt, isNotNull, reason: 'Sales history would show this sale as not voided (and offer "void" again)');
    engine.dispose();
  });

  // ================================================================ TC-SYNC-NEW-18 through the real edit form
  testWidgets('TC-SYNC-NEW-18 edit form on phone B: clear Barcode and the wholesale price, warranty "မရှိ", '
      '"သက်တမ်း မမှတ်ပါ" → the upsertProduct unit sends all four as null (keys present) → phone A, which had the '
      'values, shows them empty and finds no product for the old barcode', (tester) async {
    final bdb = memoryDb();
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(() async {
          await bdb.close();
          await adb.close();
        }));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network()); // B offline: the unit stays in the outbox
    }
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(bdb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          initialLimitsProvider.overrideWithValue(bundledLimits()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(bdb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    c.read(shopTemplateProvider.notifier).select('pharmacy');
    await settle(tester);
    for (final f in [FeatureFlag.quotation, FeatureFlag.serialWarranty, FeatureFlag.expiryBatch]) {
      await drive(tester, () async => c.read(tenantFeaturesProvider.notifier).set(f, true));
    }
    await settle(tester);

    final t = DateTime.utc(2026, 11, 1);
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA r10 form', cost: 100, price: 150, category: 'x',
        barcode: '8850000010099', wholesalePrice: 140, warrantyMonths: 6, expiryAlertDays: 30, tint: 0, initial: 'Q',
        createdAt: t, updatedAt: t);
    await drive(tester, () => c.read(productServiceProvider).create(p));
    final original = productWire((await tester.runAsync(
        () => (bdb.select(bdb.products)..where((x) => x.id.equals(p.id))).getSingle()))!);
    await tester.runAsync(() => bdb.delete(bdb.outbox).go());

    c.read(appRouterProvider).go(Routes.editProduct(p.id));
    await settle(tester);
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsOneWidget);
    Finder input(String text) => find.byWidgetPredicate((w) => w is EditableText && w.controller.text == text);
    await tester.enterText(input('8850000010099'), '');
    await tester.enterText(input('140'), '');
    await settle(tester);
    await tester.ensureVisible(find.text('၆ လ'));
    await tester.tap(find.text('၆ လ'));
    await settle(tester);
    await tester.tap(find.text('မရှိ').last);
    await settle(tester);
    await pickExpiryWarn(tester, noExpiryLabel);
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await settle(tester);
    await settle(tester);
    expect(find.text('ပစ္စည်း ပြင်မယ်'), findsNothing, reason: 'saved');

    final units = (await tester.runAsync(() => bdb.select(bdb.outbox).get()))!;
    expect(units.map((u) => u.kind), ['upsertProduct']);
    final sent = ((jsonDecode(units.single.rowsJson) as Map)['products'] as List).cast<Map>().single;
    const cleared = ['barcode', 'wholesalePrice', 'warrantyMonths', 'expiryAlertDays'];
    expect({for (final k in cleared) k: (sent.containsKey(k), sent[k])}, {for (final k in cleared) k: (true, null)},
        reason: 'B sends the cleared fields as explicit nulls');

    // phone A had the old row; it pulls B's edit (the server stores and returns nulls: b/…/SyncTests.cs
    // A_cleared_field_is_stored_as_null_and_pulled_as_an_explicit_null, and the live files)
    final aStore = SyncStore(adb, tenantId: shop.tenantId, deviceId: 'phone-a');
    await tester.runAsync(() async {
      await aStore.mergePage(page({'products': [jsonDecode(jsonEncode(original)) as Map<String, dynamic>]}, cursor: '01'));
      await aStore.mergePage(page({'products': [jsonDecode(jsonEncode(sent)) as Map<String, dynamic>]}, cursor: '02'));
    });
    final onA = (await tester.runAsync(() => adb.select(adb.products).getSingle()))!;
    expect((onA.barcode, onA.wholesalePrice, onA.warrantyMonths, onA.expiryAlertDays), (null, null, null, null));
    final byOldCode = (await tester.runAsync(
        () => (adb.select(adb.products)..where((x) => x.barcode.equals('8850000010099'))).get()))!;
    expect(byOldCode, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  });
}
