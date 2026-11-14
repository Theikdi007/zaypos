import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// BUG-10: a "v2" (soon) shop template cannot be chosen at registration.
void main() {
  setUpAll(loadAppFonts);

  bool selected(WidgetTester tester, String label) => tester
      .widget<Semantics>(find
          .ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true))
          .first)
      .properties
      .selected == true;

  testWidgets('tapping the v2 restaurant card keeps the previous choice; a normal card can be chosen', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeOverrides(boot: BootState(deviceId: newId())));
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go('${Routes.register}?step=2');
    await tester.pumpAndSettle();

    await tester.tap(find.text('ဆေးဆိုင်'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'ဆေးဆိုင်'), isTrue);

    await tester.ensureVisible(find.text('စားသောက် / ကော်ဖီ'));
    await tester.tap(find.text('စားသောက် / ကော်ဖီ'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'စားသောက် / ကော်ဖီ'), isFalse);
    expect(selected(tester, 'ဆေးဆိုင်'), isTrue, reason: 'unchanged');
  });
}
