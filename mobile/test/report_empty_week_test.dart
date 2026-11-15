import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';
import 'sync_screens_test.dart' show settle;

/// BUG-35: the report's 7-day chart with no sales in the week (a new shop on day 1) — no 0/0 bar heights, and
/// "ရောင်းအား မရှိသေးပါ" instead of an empty chart.
void main() {
  setUpAll(loadAppFonts);

  List<String> errors(WidgetTester tester) => [
        for (Object? e = tester.takeException(); e != null; e = tester.takeException()) e.toString().split('\n').first,
      ];

  testWidgets('an empty week: no layout error, 7 flat bars with "0", the empty message, and a Burmese semantics label',
      (tester) async {
    final db = memoryDb();
    addTearDown(() => tester.runAsync(db.close));
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, seed: false, overrides: [
          syncApiProvider.overrideWithValue(FakeSyncApi()),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    c.read(appRouterProvider).go(Routes.reports);
    await settle(tester);

    expect(errors(tester), isEmpty);
    expect(find.byKey(const ValueKey('weekChartEmpty')), findsOneWidget);
    expect(find.text('ရောင်းအား မရှိသေးပါ'), findsOneWidget);
    final bars = tester.widgetList<Container>(find.descendant(
        of: find.bySemanticsLabel(RegExp('နောက်ဆုံး ၇ ရက်.*ရောင်းအား မရှိသေးပါ')), matching: find.byType(Container)));
    expect(bars.where((b) => b.constraints?.maxHeight == 0), hasLength(7), reason: 'every bar is flat, none is NaN');
  });

  testWidgets('a week with sales: bars as before, no empty message', (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.reports);
    await tester.pumpAndSettle();

    expect(errors(tester), isEmpty);
    expect(find.byKey(const ValueKey('weekChartEmpty')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('အမြင့်ဆုံးက')), findsOneWidget);
  });
}
