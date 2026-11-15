import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/common.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// BUG-8: on a 320 px wide phone the Customers filter chips scroll sideways
/// instead of overflowing.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('Customers at 320 × 568: no overflow; the chips row scrolls and every chip can be reached', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.customers);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final chips = find.byWidgetPredicate((w) => w is FilterChips);
    expect(find.descendant(of: chips, matching: find.byType(SingleChildScrollView)), findsOneWidget);
    await tester.ensureVisible(find.text('အားလုံး'));
    await tester.tap(find.text('အားလုံး'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
