// QA round 10 — b04dc07 (BUG-30) and ab92a09 (BUG-29), adversarial, on the real local database + the real engine.
//
// Owner, 2026-11-14 (hand-over):
// - BUG-30: "when a pull fails, the Settings sync card shows a Burmese message; raw errors go only to the log." Also push
//   failures, the sync chip, the first-download screen, and any other place lastError is shown.
// - BUG-29: "show table and field names in Burmese on the rejected-unit screen; no internal names." Every table/column in
//   editableColumns, unknown tables, and the validation error texts on that screen.
// Allowed English (owner, TC-UX-02): KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP, Stock, Sync, Batch.
// The text checker (badStrings) is the round-9 one: Latin words outside the allow-list, after removing user data.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import '../sync_screens_test.dart' show drive, settle;
import 'qa_round9_sync_text_test.dart' show badStrings, issueRow, screenTexts;

/// A pull that fails with a non-API error (e.g. the phone's storage is full).
class _BrokenPullApi extends FakeSyncApi {
  Object? pullThrows;
  @override
  Future<PullPage> pull(String cursor, {int limit = 500}) async {
    final e = pullThrows;
    if (e != null) throw e;
    return super.pull(cursor, limit: limit);
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<(ProviderContainer, TestShop, AppDatabase, _BrokenPullApi)> boot(WidgetTester tester,
      {bool initialDone = true}) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = _BrokenPullApi();
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          initialLimitsProvider.overrideWithValue(bundledLimits()),
        ])))!;
    addTearDown(c.dispose);
    if (initialDone) {
      await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    }
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    return (c, shop, adb, api);
  }

  /// Like settle, for the first-sync screen (its progress bar never settles).
  Future<void> spin(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  }

  testWidgets('TC-UX-NEW-8 Settings sync card after every kind of failed cycle — unreadable pulled row, a pulled row of '
      'the wrong type (TypeError), a non-API exception in the pull, push: no network / 500 with an English detail / an '
      'unknown English error code: the card shows exactly the Burmese message, never the raw error', (tester) async {
    final (c, shop, adb, api) = await boot(tester);
    final tid = shop.tenantId;
    final t = DateTime.utc(2026, 11, 14, 9);
    c.read(appRouterProvider).go(Routes.settingsFeatures);
    await settle(tester);

    final seen = <String, String?>{};
    final found = <String, List<String>>{};
    Future<void> cycle(String name, {required String expected, List<String> raw = const []}) async {
      await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
      await settle(tester);
      final error = c.read(syncEngineProvider).snapshot.lastError;
      seen[name] = error;
      final all = screenTexts(tester).join('\n');
      if (error != expected) found[name] = ['lastError = "$error", expected "$expected"'];
      if (find.text(expected).evaluate().isEmpty) (found[name] ??= []).add('card does not show the message');
      for (final r in raw) {
        if (all.contains(r)) (found[name] ??= []).add('raw text on screen: $r');
      }
      if (badStrings(tester) case final b when b.isNotEmpty) (found[name] ??= []).addAll(b);
    }

    // pull: a row without a required field (FormatException)
    api.pages.add(page({'syncIssues': [issueRow(tid, 'duplicateBarcode', 'x', null, t)..remove('kind')]}, cursor: 'A1'));
    await cycle('pull FormatException', expected: SyncMessages.unreadable, raw: ['FormatException', 'syncIssues.kind']);
    api.pages.clear();

    // pull: a field of the wrong type (a newer server sends deletedAt as a number) → TypeError, not FormatException
    api.pages.add(page({
      'customers': [
        {'id': newId(), 'tenantId': tid, 'name': 'Ma Ma', 'phone': '09790010003', 'createdAt': '2026-11-14T08:00:00Z',
          'updatedAt': '2026-11-14T09:00:00Z', 'deletedAt': 1763100000000},
      ],
    }, cursor: 'A2'));
    await cycle('pull TypeError', expected: SyncMessages.failed, raw: ['TypeError', "'int'", 'String']);
    api.pages.clear();

    // pull: anything else (storage full)
    api.pullThrows = StateError('SqliteException(13): database or disk is full');
    await cycle('pull StateError', expected: SyncMessages.failed, raw: ['Sqlite', 'disk is full', 'Bad state']);
    api.pullThrows = null;

    // push failures: a pending unit first
    final cu = Customer(id: newId(), tenantId: tid, name: 'Ko Ko', phone: '09790010004', createdAt: t, updatedAt: t);
    for (var i = 0; i < 20; i++) {
      api.pushErrors.add(const ApiError.network()); // the app's own debounced cycles stay offline
    }
    await drive(tester, () => c.read(customerServiceProvider).create(cu));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect((await tester.runAsync(() => adb.select(adb.outbox).get()))!.map((o) => o.status.name), ['pending']);
    api.pushErrors
      ..clear()
      ..add(const ApiError.network('SocketException: Connection refused (OS Error: 61)'));
    await cycle('push network', expected: apiErrorMessage('network'), raw: ['SocketException', 'Connection refused']);
    api.pushErrors
      ..clear()
      ..add(const ApiError(500, 'server', detail: 'SqlException: Execution Timeout Expired.'));
    await cycle('push 500', expected: apiErrorMessage('server'), raw: ['SqlException', 'Timeout']);
    api.pushErrors
      ..clear()
      ..add(const ApiError(400, 'One or more validation errors occurred.', detail: 'The deviceId field is required.'));
    await cycle('push unknown English code', expected: apiErrorMessage('?'), raw: ['validation errors', 'deviceId']);
    api.pushErrors.clear();

    // success clears the card
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    await settle(tester);
    final after = c.read(syncEngineProvider).snapshot.lastError;

    await end(tester);
    expect(found, isEmpty,
        reason: '${found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n')}\nall: $seen');
    expect(after, isNull, reason: 'a good cycle clears the message');
  });

  testWidgets('TC-UX-NEW-8 first-download screen (new phone): an unreadable row, then a storage error → Burmese only, '
      'with "ပြန်ကြိုးစားမယ်"; the raw error is never shown', (tester) async {
    final (c, shop, _, api) = await boot(tester, initialDone: false);
    c.read(firstSyncDoneProvider.notifier).set(false); // a new phone: what the login does (auth_controller)
    await spin(tester);
    expect(find.textContaining('ဆိုင်ဒေတာ ဒေါင်းနေသည်'), findsOneWidget, reason: 'the first-sync screen is shown');
    final row = issueRow(shop.tenantId, 'duplicateBarcode', 'x', null, DateTime.utc(2026, 11, 14))..remove('kind');
    api.pages.add(page({'syncIssues': [row]}, cursor: 'B1'));
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    await spin(tester);
    final first = (find.text(SyncMessages.unreadable).evaluate().length, badStrings(tester).join(),
        screenTexts(tester).any((s) => s.contains('FormatException')));
    api.pages.clear();
    api.pullThrows = StateError('SqliteException(13): database or disk is full');
    await tester.tap(find.text('ပြန်ကြိုးစားမယ်'));
    await spin(tester);
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));
    await spin(tester);
    final second = (find.text(SyncMessages.failed).evaluate().length, badStrings(tester).join(),
        screenTexts(tester).any((s) => s.contains('Sqlite') || s.contains('Bad state')));
    await end(tester);
    expect(first, (1, '', false));
    expect(second, (1, '', false));
  });

  testWidgets('TC-UX-NEW-9 rejected-unit screen with a row in EVERY editableColumns table + an unknown table: each field '
      'is labelled "<table> · <field>" in Burmese (exact list), the unknown table shows no field and no name, and the '
      'validation errors (required, too long, non-ASCII Barcode / IMEI) are Burmese', (tester) async {
    final (c, _, adb, _) = await boot(tester);
    final rows = {
      'products': [{'id': 'p1', 'name': 'Sprite can', 'category': 'Drinks', 'unit': 'can', 'barcode': '885001'}],
      'customers': [{'id': 'c1', 'name': 'Ma Ma', 'phone': '0979001', 'address': 'Yangon', 'note': 'VIP'}],
      'productVariants': [{'id': 'v1', 'productId': 'p1', 'size': 'XL', 'color': 'Red'}],
      'productBatches': [{'id': 'b1', 'productId': 'p1', 'batchNo': 'LOT7'}],
      'productSerials': [{'id': 's1', 'productId': 'p1', 'serial': '359000001'}],
      'sales': [{'id': 'sa1', 'no': 'A-0009', 'customerName': 'Ma Ma', 'total': 900}],
      'saleLines': [{'id': 'l1', 'saleId': 'sa1', 'name': 'Sprite can'}],
      'stockMovements': [{'id': 'm1', 'productId': 'p1', 'note': 'opening'}],
      'debtEntries': [{'id': 'd1', 'customerId': 'c1', 'note': 'paid'}],
      'loyaltyCards': [{'id': 'k1', 'name': 'Gold card', 'note': 'secretNote'}],
    };
    await tester.runAsync(() => adb.into(adb.outbox).insert(OutboxCompanion.insert(
          unitId: newId(), kind: 'checkout', rowsJson: jsonEncode(rows), clientTime: 1763100000000,
          status: const Value(OutboxStatus.rejected), rejectReason: const Value('products.name is longer than 150 characters.'),
          rejectCode: const Value('fieldTooLong'), rejectData: const Value('{"field":"products.name","max":"150"}'),
        )));
    final seq = (await tester.runAsync(() => adb.select(adb.outbox).get()))!.single.seq;
    c.read(appRouterProvider).push(Routes.rejectedUnit(seq));
    await settle(tester);

    final labels = screenTexts(tester).where((s) => s.contains(' · ')).where((s) => !s.startsWith('ရောင်းချမှု')).toList();
    expect(labels, [
      'ပစ္စည်း · အမည်', 'ပစ္စည်း · အမျိုးအစား', 'ပစ္စည်း · ယူနစ်', 'ပစ္စည်း · Barcode',
      'ဖောက်သည် · အမည်', 'ဖောက်သည် · ဖုန်း', 'ဖောက်သည် · လိပ်စာ', 'ဖောက်သည် · မှတ်ချက်',
      'ဆိုဒ် / အရောင် · ဆိုဒ်', 'ဆိုဒ် / အရောင် · အရောင်', 'Batch · Batch', 'IMEI · IMEI / စီးရီးနံပါတ်',
      'ပြေစာ · ဖောက်သည်အမည်', 'ပြေစာထဲက ပစ္စည်း · အမည်', 'Stock အဝင်အထွက် · မှတ်ချက်', 'အကြွေးစာရင်း · မှတ်ချက်',
    ]);
    expect(find.text('“အမည်” က စာလုံး ၁၅၀ လုံးထက် ရှည်နေပါတယ်။'), findsOneWidget);
    const userData = {'Sprite can', 'Drinks', 'can', 'Ma Ma', 'Yangon', 'VIP', 'XL', 'Red', 'LOT7', 'opening', 'paid',
      'A-0009'};
    final screen1 = badStrings(tester, data: userData);
    final all = screenTexts(tester).join('\n');
    final internal = ['loyaltyCards', 'Gold card', 'secretNote', 'products', 'customers', 'productVariants', 'saleLines',
      'stockMovements', 'debtEntries', 'customerName', 'batchNo'].where(all.contains).toList();

    // validation: required name cleared, too long category, non-ASCII barcode and IMEI
    Finder input(String text) => find.byWidgetPredicate((w) => w is EditableText && w.controller.text == text);
    await tester.enterText(input('Sprite can').first, '');
    await tester.enterText(input('Drinks'), 'က' * 61);
    await tester.enterText(input('885001'), 'ကခ၁');
    await tester.enterText(input('359000001'), 'IMEI-ဆ');
    await tester.ensureVisible(find.text('ပြင်ပြီး ပြန်ပို့မယ်'));
    await tester.tap(find.text('ပြင်ပြီး ပြန်ပို့မယ်'));
    await settle(tester);
    final errors = {
      'အမည် ထည့်ပါ။': find.text('အမည် ထည့်ပါ။').evaluate().length,
      'အမျိုးအစား စာလုံး ၆၀ လုံးထက် မပိုရပါ။': find.text('အမျိုးအစား စာလုံး ၆၀ လုံးထက် မပိုရပါ။').evaluate().length,
      'Barcode မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။':
          find.text('Barcode မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။').evaluate().length,
      'IMEI / စီးရီးနံပါတ် မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။':
          find.text('IMEI / စီးရီးနံပါတ် မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။').evaluate().length,
    };
    final screen2 = badStrings(tester, data: {...userData, 'IMEI-ဆ'});
    final stillRejected = (await tester.runAsync(() => adb.select(adb.outbox).get()))!.single.status;
    await end(tester);
    expect(screen1, isEmpty);
    expect(internal, isEmpty, reason: 'internal table / column names or the unknown table\'s data on screen');
    expect(errors, {for (final k in errors.keys) k: 1}, reason: 'Burmese validation errors, each under its field');
    expect(screen2, isEmpty);
    expect(stillRejected, OutboxStatus.rejected, reason: 'invalid edits are not sent');
  });
}
