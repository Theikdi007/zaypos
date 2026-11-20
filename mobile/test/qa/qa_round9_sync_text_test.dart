// QA round 9 — BUG-26 (7df5f1f): issue / rejection messages built in the app, in Burmese, from structured server fields.
//
// Owner (hand-over): "issue/rejection messages must be built in the app in Burmese from the issue type plus structured
// fields (barcode, product names, IMEI, amounts). If the server only sends English text today, add structured fields to
// the issue payload (keep the old text field for compatibility). Unknown issue types show a generic Burmese message. No
// internal names on screen."  Allowed English (owner, TC-UX-02): KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP,
// Stock, Sync, Batch (+ brand, Ks, units). User data (product / customer names, barcodes) is not app text.
//
// What the developer's m/no_english_test.dart does not do, and this file does:
// - issues arrive by a PULL through the real engine + WireDecoder (data as the JSON string SyncIssueRow.Data is on the
//   wire, built exactly like UnitApplier.Issue(...) / SyncIssueData.Serialize), rejections by a PUSH result;
// - user data in English (real shops type "Coca-Cola", "iPhone 13") must not confuse the message;
// - an app on Drift schema v1 with old issues and a rejected unit upgrades and shows Burmese on the screens;
// - the Settings sync card / first-sync screen error text (snapshot.lastError) for a row the app cannot read.
// The same functions are checked against the REAL server's payloads in m/qa/live_qa_round9_test.dart.
import 'dart:convert';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../generated_migrations/schema.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show drive, settle;

const _allowedLatin = {
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch',
  'zaypos', 'ks', 'ml', 'l', 'kg', 'xx', 'xxx',
};

/// Internal names that must never be on screen (wire keys, issue kinds, unit kinds, reject codes, tables).
const _internal = [
  'productName', 'othersCount', 'others', 'stockMilli', 'customerName', 'minutesAhead', 'clampMinutes', 'receiptNo',
  'storedAs', 'serverTotal', 'clientTotal', 'duplicateBarcode', 'duplicateSerial', 'serialDoubleSold', 'negativeStock',
  'creditLimitExceeded', 'clockSkew', 'totalMismatch', 'duplicateReceiptNo', 'upsertCustomer', 'upsertProduct',
  'fieldTooLong', 'fieldNotAscii', 'customers.phone', 'products.name', 'FormatException', 'syncIssues', 'Products',
];

List<String> screenTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
    ];

/// Latin words outside the allow-list (after removing [data] = user data) and internal names, in every Text on screen.
List<String> badStrings(WidgetTester tester, {Set<String> data = const {}}) {
  final bad = <String>{};
  for (final raw in screenTexts(tester)) {
    var s = raw;
    // longest first, so "Galaxy A15" is removed before "A1"; the fixture shop name is user data too
    for (final d in ([...data, 'Test shop']..sort((a, b) => b.length.compareTo(a.length)))) {
      s = s.replaceAll(d, '');
    }
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(s).map((m) => m.group(0)!.toLowerCase());
    final unknown = words.where((w) => !_allowedLatin.contains(w)).toSet();
    final internal = _internal.where(s.contains);
    if (unknown.isNotEmpty || internal.isNotEmpty) bad.add('"$raw" (English: ${{...unknown, ...internal}.join(', ')})');
  }
  return bad.toList();
}

/// Same shape as backend SyncIssueRow on the pull wire (camelCase; data = the JSON object string).
Map<String, dynamic> issueRow(String tid, String kind, String detail, Map<String, Object?>? data, DateTime at,
        {String? id}) =>
    {
      'id': id ?? newId(), 'tenantId': tid, 'kind': kind, 'entityTable': 'Products', 'entityId': newId(), 'detail': detail,
      'data': data == null ? null : jsonEncode(data), 'deviceId': null, 'resolvedAt': null,
      'createdAt': at.toIso8601String(), 'updatedAt': at.toIso8601String(), 'deletedAt': null,
    };

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-UX-NEW-5 pulled issues of every kind (server data shape, English user data) and a pushed rejection: '
      '"စစ်ရန်", the rejected-unit screen and the sync chip are Burmese with the right names / numbers, never the server\'s '
      'English or an internal name', (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi()
      ..outcome = ((u) => u.kind == 'upsertCustomer' ? UnitOutcome.rejected : UnitOutcome.applied)
      ..rejectReason = 'customers.phone must be ASCII (digits/latin letters).'
      ..rejectCode = 'fieldNotAscii'
      ..rejectData = const {'field': 'customers.phone'};
    tester.view.physicalSize = const Size(390, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);

    final tid = shop.tenantId;
    final t = DateTime.utc(2026, 11, 14, 8);
    // Data exactly as UnitApplier builds it (dictionary keys as written; numbers as JSON numbers; ≤ 5 names + count).
    api.pages.add(page({
      'syncIssues': [
        issueRow(tid, 'duplicateBarcode', 'Barcode 8850000099001 is also used by: Coca-Cola can, Pepsi can.', {
          'barcode': '8850000099001', 'productName': 'Sprite can', 'others': ['Coca-Cola can', 'Pepsi can'],
          'othersCount': 2,
        }, t),
        issueRow(tid, 'duplicateSerial', 'Serial 359920000000001 is already in stock (iPhone 13). Both rows were kept.', {
          'serial': '359920000000001', 'productName': 'iPhone 13 Pro',
          'others': ['iPhone 13', 'A1', 'A2', 'A3', 'A4'], 'othersCount': 6,
        }, t.add(const Duration(minutes: 1))),
        issueRow(tid, 'serialDoubleSold', 'Serial 359920000000002 sold twice: sale line x and y. Both sales were kept.',
            {'serial': '359920000000002', 'productName': 'Galaxy A15'}, t.add(const Duration(minutes: 2))),
        issueRow(tid, 'negativeStock', 'Tiger beer: stock is -3 after this sync. The sale was kept.',
            {'productName': 'Tiger beer', 'stockMilli': -3000}, t.add(const Duration(minutes: 3))),
        issueRow(tid, 'creditLimitExceeded', 'Ma Ma owes 75,500 Ks, over the 50,000 Ks limit.',
            {'customerName': 'Ma Ma', 'balance': 75500, 'limit': 50000}, t.add(const Duration(minutes: 4))),
        issueRow(tid, 'clockSkew', 'Device clock is 31 min ahead of the server; edit times were clamped to server time + 5 min.',
            {'minutesAhead': 31, 'clampMinutes': 5}, t.add(const Duration(minutes: 5))),
        issueRow(tid, 'totalMismatch', 'Sale B-0007: total: client 900, server 1500',
            {'receiptNo': 'B-0007', 'clientTotal': 900, 'serverTotal': 1500}, t.add(const Duration(minutes: 6))),
        issueRow(tid, 'duplicateReceiptNo', 'Receipt B-0008 already exists (reinstalled app reusing a device code?). '
            'Stored as B-0008*2.', {'receiptNo': 'B-0008', 'storedAs': 'B-0008*2'}, t.add(const Duration(minutes: 7))),
        issueRow(tid, 'tableMerged', 'Table 4 was merged into table 5.', {'tableNo': 'Table 4'},
            t.add(const Duration(minutes: 8))),
        issueRow(tid, 'duplicateBarcode', 'Barcode 8850000099002 is also used by: Old row.', null,
            t.add(const Duration(minutes: 9))),
      ],
    }, cursor: '00000000000000AA'));
    // A customer whose phone the server refuses (a rejected unit; user data in English).
    await drive(tester, () => c.read(customerServiceProvider).create(Customer(id: newId(), tenantId: tid, name: 'Ko Aung',
        phone: '09790000999', createdAt: t, updatedAt: t)));
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    expect(c.read(syncEngineProvider).snapshot.lastError, isNull);
    final pulled = (await tester.runAsync(() => adb.select(adb.syncIssues).get()))!;
    expect(pulled, hasLength(10));
    final rejected = (await tester.runAsync(() => outbox(adb)))!.where((o) => o.status == OutboxStatus.rejected).toList();
    expect(rejected.map((o) => (o.kind, o.rejectCode)), [('upsertCustomer', 'fieldNotAscii')]);

    const userData = {
      'Sprite can', 'Coca-Cola can', 'Pepsi can', 'iPhone 13 Pro', 'iPhone 13', 'A1', 'A2', 'A3', 'A4', 'Galaxy A15',
      'Tiger beer', 'Ma Ma', 'Ko Aung', 'B-0007', 'B-0008*2', 'B-0008',
    };
    final found = <String, List<String>>{};

    // the sync chip on the dashboard
    c.read(appRouterProvider).go(Routes.dashboard);
    await settle(tester);
    expect(find.textContaining('Sync ပြဿနာ'), findsWidgets);
    if (badStrings(tester, data: userData) case final b when b.isNotEmpty) found['dashboard (sync chip)'] = b;

    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    if (badStrings(tester, data: userData) case final b when b.isNotEmpty) found['စစ်ရန်'] = b;
    final all = screenTexts(tester).join('\n');
    final expected = <String, List<String>>{
      'duplicateBarcode': ['8850000099001', '“Sprite can”', '“Coca-Cola can”', '“Pepsi can”'],
      'duplicateSerial': ['359920000000001', '“iPhone 13 Pro”', '“iPhone 13”', 'အခြား ၁ မျိုး'],
      'serialDoubleSold': ['359920000000002', '“Galaxy A15”'],
      'negativeStock': ['“Tiger beer”', '-၃'],
      'creditLimitExceeded': ['“Ma Ma”', '75,500 Ks', '50,000 Ks'],
      'clockSkew': ['၃၁ မိနစ်'],
      'totalMismatch': ['B-0007', '1,500 Ks'],
      'duplicateReceiptNo': ['B-0008', 'B-0008*2'],
      'unknown kind': ['ဆာဗာက ဒီစာရင်းကို စစ်ဖို့ အကြောင်းကြားထားပါတယ်'],
      'old row without data': ['ဒီ Barcode ကို ပစ္စည်းတွေမှာ သုံးထားပါတယ်'],
      'rejected unit': ['ဖောက်သည်အသစ် · Ko Aung', 'ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ'],
    };
    final missing = {
      for (final e in expected.entries)
        if (e.value.where((v) => !all.contains(v)).toList() case final m when m.isNotEmpty) e.key: m,
    };
    expect(missing, isEmpty, reason: 'names / numbers missing from "စစ်ရန်":\n$all');
    for (final i in pulled) {
      expect(all.contains(i.detail), isFalse, reason: 'English detail shown: ${i.detail}');
    }
    expect(all.contains(api.rejectReason), isFalse);

    c.read(appRouterProvider).push(Routes.rejectedUnit(rejected.single.seq));
    await settle(tester);
    expect(find.textContaining('ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ'), findsOneWidget);
    if (badStrings(tester, data: userData) case final b when b.isNotEmpty) found['rejected unit'] = b;

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n'));
  });

  testWidgets('TC-UX-NEW-6 an app on Drift schema v1 with an old issue and a rejected unit upgrades to v2: "စစ်ရန်" and '
      'the rejected-unit screen show Burmese (shorter sentence / generic reason), never the stored English; the next pull '
      'of the same issue with data shows the full message', (tester) async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = (await tester.runAsync(() => verifier.schemaAt(1)))!;
    final old = schema.rawDatabase;
    // an existing install: the v1 database already belongs to the shop (LocalStateKeys), so no adopt / wipe runs
    for (final (k, v) in [('ownerTenantId', 't-old'), ('ownerPhone', '+959700000001'), ('ownerDemo', 'false')]) {
      old.execute("INSERT INTO syncState (key, value) VALUES ('$k', '$v')");
    }
    const oldDetail = 'Barcode 8850000099003 is also used by: Fanta can.';
    const oldReason = 'products.name is longer than 120 characters.';
    old.execute("INSERT INTO syncIssues (id, tenantId, kind, entityTable, entityId, detail, createdAt, updatedAt) "
        "VALUES ('old-issue', 't-old', 'duplicateBarcode', 'Products', 'p1', '$oldDetail', 1763100000000, 1763100000000)");
    old.execute("INSERT INTO outbox (unitId, kind, rowsJson, clientTime, status, rejectReason) VALUES ('old-unit', "
        "'upsertProduct', '{\"products\":[{\"id\":\"p9\",\"name\":\"Fanta can\"}]}', 1763100000000, 'rejected', '$oldReason')");
    final adb = AppDatabase(schema.newConnection());
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi()..outcome = ((_) => UnitOutcome.rejected);
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    expect((await tester.runAsync(() => adb.customSelect('PRAGMA user_version').getSingle()))!.data.values.single, 3); // v1 → current (v3 since BUG-61)
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);

    final found = <String, List<String>>{};
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    var all = screenTexts(tester).join('\n');
    expect(all, contains('ဒီ Barcode ကို ပစ္စည်းတွေမှာ သုံးထားပါတယ်'));
    expect(all, contains('ဆာဗာက ဒီစာရင်းကို လက်မခံပါ'));
    expect(all.contains(oldDetail) || all.contains(oldReason), isFalse, reason: all);
    if (badStrings(tester, data: {'Fanta can'}) case final b when b.isNotEmpty) found['စစ်ရန် after upgrade'] = b;
    final seq = (await tester.runAsync(() => outbox(adb)))!.single.seq;
    c.read(appRouterProvider).push(Routes.rejectedUnit(seq));
    await settle(tester);
    if (badStrings(tester, data: {'Fanta can'}) case final b when b.isNotEmpty) found['rejected unit after upgrade'] = b;

    // the server re-sends the same issue id, now with data (a v2 server) → full message
    final t = DateTime.utc(2026, 11, 14, 9);
    api.pages.add(page({
      'syncIssues': [
        {
          ...issueRow(shop.tenantId, 'duplicateBarcode', oldDetail,
              {'barcode': '8850000099003', 'productName': 'Mirinda can', 'others': ['Fanta can'], 'othersCount': 1}, t,
              id: 'old-issue'),
        },
      ],
    }, cursor: '00000000000000BB'));
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    await settle(tester);
    all = screenTexts(tester).join('\n');
    expect(all, contains('Barcode 8850000099003 ကို “Mirinda can” နဲ့ “Fanta can”'));

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n'));
  });

  testWidgets('TC-UX-NEW-7 a pulled row the app cannot read: the Settings sync card shows a Burmese error, not the '
      'exception text (FormatException / table.column)', (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    // e.g. a newer server that sends a row without a field this app needs
    final row = issueRow(shop.tenantId, 'duplicateBarcode', 'x', null, DateTime.utc(2026, 11, 14))..remove('kind');
    api.pages.add(page({'syncIssues': [row]}, cursor: '00000000000000CC'));
    c.read(appRouterProvider).go(Routes.settingsFeatures);
    await settle(tester);
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    await settle(tester);
    final error = c.read(syncEngineProvider).snapshot.lastError;
    expect(error, isNotNull);
    expect(find.text(error!), findsOneWidget, reason: 'the card shows snapshot.lastError');
    final bad = badStrings(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
    expect(bad, isEmpty, reason: 'phase3-sync.md: map codes to Burmese messages; owner: no internal names on screen');
  });
}
