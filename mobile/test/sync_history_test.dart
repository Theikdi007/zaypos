import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';
import 'sync_screens_test.dart' show settle;

/// Owner 2026-11-14: the server closes a duplicateBarcode issue once no other product has the barcode
/// (data.resolution "fixed"). Every phone pulls it: it leaves the open list and shows in the history as
/// "ပြင်ပြီးသွားပါပြီ" (an owner-resolved one as "စစ်ပြီးပြီ").
void main() {
  setUpAll(loadAppFonts);
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Map<String, dynamic> issue(String tenantId, String id, {String? resolvedAt, String? data}) => {
        'id': id, 'tenantId': tenantId, 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': 'p-$id',
        'detail': 'Barcode 885 is also used by: x.', 'data': data, 'deviceId': null, 'resolvedAt': resolvedAt,
        'createdAt': '2026-11-14T08:00:00Z', 'updatedAt': resolvedAt ?? '2026-11-14T08:00:00Z', 'deletedAt': null,
      };

  testWidgets('a pulled server-resolved issue moves to the history as "ပြင်ပြီးသွားပါပြီ"; owner-resolved as "စစ်ပြီးပြီ"',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, overrides: [
          syncApiProvider.overrideWithValue(FakeSyncApi()),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    const data = '{"barcode":"8850000099105","productName":"က","others":["ခ"],"othersCount":1}';
    await tester.runAsync(() => store.mergePage(page({
          'syncIssues': [issue(shop.tenantId, 'auto', data: data), issue(shop.tenantId, 'manual', data: data)],
        }, cursor: '0000000000000001')));
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    expect(find.text('စစ်ရန် (၂)'), findsOneWidget);
    expect(find.text('ပြီးသွားတဲ့ ကိစ္စများ'), findsNothing);

    // B cleared the barcode → the server closed one issue itself; the owner marked the other one reviewed.
    await tester.runAsync(() => store.mergePage(page({
          'syncIssues': [
            issue(shop.tenantId, 'auto', resolvedAt: '2026-11-14T10:00:00Z',
                data: '{"barcode":"8850000099105","productName":"က","others":["ခ"],"othersCount":1,"resolution":"fixed"}'),
            issue(shop.tenantId, 'manual', resolvedAt: '2026-11-14T09:00:00Z', data: data),
          ],
        }, cursor: '0000000000000002')));
    await settle(tester);
    expect(find.text('စစ်ရန် (၀)'), findsOneWidget);
    expect(find.text('ပြီးသွားတဲ့ ကိစ္စများ'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('resolvedIssue-auto')), matching: find.text('ပြင်ပြီးသွားပါပြီ')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('resolvedIssue-manual')), matching: find.text('စစ်ပြီးပြီ')),
        findsOneWidget);
    expect(await db.select(db.syncIssues).get(), hasLength(2), reason: 'kept as history');
  });
}
