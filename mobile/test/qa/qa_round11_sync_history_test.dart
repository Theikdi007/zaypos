// QA round 11 — 1420ee8 (duplicate-barcode issues close themselves), the app side, and one report finding.
//
// Owner: "the server closes it automatically once no other product in the shop has that barcode. Mark it resolved with a
// reason ('ပြင်ပြီးသွားပါပြီ'), keep it in history, and show the resolved state on every phone." App: "စစ်ရန်" history
// section "ပြီးသွားတဲ့ ကိစ္စများ" (latest 30), "ပြင်ပြီးသွားပါပြီ" (data.resolution "fixed") vs owner-resolved "စစ်ပြီးပြီ".
//
// What the developer's m/sync_history_test.dart does not do, and this file does: the 30-row limit and its order with more
// than 30 resolved issues, a deleted issue, an old issue closed by the server (data was NULL → {"resolution":"fixed"}),
// a NEW issue for the same barcode after the old one was fixed (open + history), a re-pull of the same resolved rows
// (BUG-32 rewind: nothing re-raised or duplicated), the title count, and no English in the history.
// TC-RPT-NEW-1 (found while checking day totals for BUG-32): the report screen of a shop with no sales in the last 7 days.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show settle;
import 'qa_round9_sync_text_test.dart' show badStrings;

String _c(int n) => n.toRadixString(16).padLeft(16, '0');

void main() {
  setUpAll(loadAppFonts);

  Map<String, dynamic> issue(String tid, String id, {DateTime? resolvedAt, Map<String, Object?>? data, String? deletedAt,
          DateTime? createdAt}) =>
      {
        'id': id, 'tenantId': tid, 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': 'p-$id',
        'detail': 'Barcode 8850000011099 is also used by: Coke B.', 'data': data == null ? null : jsonEncode(data),
        'deviceId': null, 'resolvedAt': resolvedAt?.toIso8601String(),
        'createdAt': (createdAt ?? DateTime.utc(2026, 11, 1)).toIso8601String(),
        'updatedAt': (resolvedAt ?? createdAt ?? DateTime.utc(2026, 11, 1)).toIso8601String(), 'deletedAt': deletedAt,
      };
  const fields = {'barcode': '8850000011099', 'productName': 'Coke A', 'others': ['Coke B'], 'othersCount': 1};

  Future<(ProviderContainer, SyncStore, AppDatabase, String)> boot(WidgetTester tester) async {
    final db = memoryDb();
    addTearDown(() => tester.runAsync(db.close));
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, seed: false, overrides: [
          syncApiProvider.overrideWithValue(FakeSyncApi()),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await tester.runAsync(store.markInitialSyncDone);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    return (c, store, db, shop.tenantId);
  }

  testWidgets('TC-SYNC-NEW-26 history: 33 resolved issues + 1 deleted + 1 open → "စစ်ရန် (၁)", the open one in '
      '"စစ်ဆေးရန် ကိစ္စများ", exactly the 30 newest resolutions in "ပြီးသွားတဲ့ ကိစ္စများ" (newest first), the deleted one '
      'nowhere; "ပြင်ပြီးသွားပါပြီ" for server-closed (incl. an old issue whose data was only {"resolution":"fixed"}), '
      '"စစ်ပြီးပြီ" for owner-resolved; no English', (tester) async {
    final (c, store, db, tid) = await boot(tester);
    final base = DateTime.utc(2026, 11, 14, 6);
    final rows = [
      for (var i = 0; i < 33; i++)
        issue(tid, 'r$i', resolvedAt: base.add(Duration(minutes: i)),
            data: i == 32 ? {'resolution': 'fixed'} : (i.isEven ? {...fields, 'resolution': 'fixed'} : fields)),
      issue(tid, 'deleted', resolvedAt: base.add(const Duration(hours: 5)), data: {...fields, 'resolution': 'fixed'},
          deletedAt: base.add(const Duration(hours: 5)).toIso8601String()),
      issue(tid, 'open', data: fields, createdAt: base.add(const Duration(hours: 6))),
    ];
    await tester.runAsync(() => store.mergePage(page({'syncIssues': rows}, cursor: _c(1))));
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);

    expect(find.text('စစ်ရန် (၁)'), findsOneWidget);
    expect(find.text('စစ်ဆေးရန် ကိစ္စများ'), findsOneWidget);
    expect(find.text('ပြီးသွားတဲ့ ကိစ္စများ'), findsOneWidget);
    final shown = [
      for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('resolvedIssue-')).evaluate())
        (e.widget.key! as ValueKey<String>).value.substring('resolvedIssue-'.length),
    ];
    expect(shown, [for (var i = 32; i >= 3; i--) 'r$i'], reason: 'the 30 newest resolutions, newest first');
    String label(String id) => tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('resolvedIssue-$id')),
        matching: find.byWidgetPredicate((w) => w is Text && (w.data == 'ပြင်ပြီးသွားပါပြီ' || w.data == 'စစ်ပြီးပြီ')))).data!;
    expect({for (final id in ['r32', 'r31', 'r30']) id: label(id)},
        {'r32': 'ပြင်ပြီးသွားပါပြီ', 'r31': 'စစ်ပြီးပြီ', 'r30': 'ပြင်ပြီးသွားပါပြီ'});
    expect(find.descendant(of: find.byKey(const ValueKey('resolvedIssue-r32')),
        matching: find.textContaining('ဒီ Barcode ကို')), findsOneWidget, reason: 'old issue: the shorter sentence');
    expect(find.descendant(of: find.byKey(const ValueKey('resolvedIssue-r30')),
        matching: find.textContaining('Barcode 8850000011099 ကို')), findsOneWidget);
    expect(badStrings(tester, data: {'Coke A', 'Coke B'}), isEmpty);
  });

  testWidgets('TC-SYNC-NEW-26 a new duplicate of the same barcode after the old issue was fixed: the NEW issue is open, '
      'the old one stays in the history as "ပြင်ပြီးသွားပါပြီ"; a re-pull of the same rows (cursor rewound) re-raises '
      'nothing and duplicates nothing', (tester) async {
    final (c, store, db, tid) = await boot(tester);
    final fixedAt = DateTime.utc(2026, 11, 14, 7);
    final old = issue(tid, 'old', resolvedAt: fixedAt, data: {...fields, 'resolution': 'fixed'});
    final fresh = issue(tid, 'new', data: fields, createdAt: DateTime.utc(2026, 11, 14, 8));
    await tester.runAsync(() => store.mergePage(page({'syncIssues': [old, fresh]}, cursor: _c(2))));
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    expect(find.text('စစ်ရန် (၁)'), findsOneWidget);
    expect(find.byKey(const ValueKey('resolvedIssue-old')), findsOneWidget);
    expect(find.byKey(const ValueKey('resolvedIssue-new')), findsNothing);
    expect(find.text('စစ်ပြီးပြီ'), findsOneWidget, reason: 'the owner button of the open (new) issue only');

    await tester.runAsync(() => db.writeState('pullCursor', '0'));
    await tester.runAsync(() => store.mergePage(page({'syncIssues': [old, fresh]}, cursor: _c(2))));
    await settle(tester);
    expect(find.text('စစ်ရန် (၁)'), findsOneWidget);
    expect((await tester.runAsync(() => db.select(db.syncIssues).get()))!.length, 2);
  });

  testWidgets('TC-RPT-NEW-1 a shop with no sales in the last 7 days (a new shop, or every sale voided) opens the report '
      'screen without a layout error', (tester) async {
    final (c, _, _, _) = await boot(tester);
    c.read(appRouterProvider).go(Routes.reports);
    await settle(tester);
    final errors = <String>[];
    for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
      errors.add(e.toString().split('\n').first);
    }
    expect(errors, isEmpty, reason: 'the 7-day chart divides by the week\'s highest day (0)');
  });
}
