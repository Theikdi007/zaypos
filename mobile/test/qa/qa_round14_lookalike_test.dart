// QA round 14 — TC-UX-NEW-14 (new): things that LOOK like the tappable control next to them but have no handler at all
// (the static scan and the GestureDetector sweep cannot see them, because there is nothing to find). Fake repos, 390×844.
//  - Dashboard "အကြွေးရရန်" card: same StatCard as "Stock နည်းနေသည်" beside it, which opens Products (low stock).
//  - Dashboard "နောက်ဆုံး အရောင်းများ" rows: the same SaleRow that opens the sale on the Sales screen.
//  (Sales history "ယနေ့", now a label drawn like SmallOutlineButton, is judged on the simulator screenshot, not here.)
// Expected (owner's rule for BUG-40/46): a control that looks ready does something, or does not look like a control.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/primary_button.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-UX-NEW-14 dashboard debt card / recent sale rows react like their twins', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final router = c.read(appRouterProvider);
    String loc() => router.routerDelegate.currentConfiguration.uri.toString();

    Future<String> tapOn(String what, Finder f) async {
      router.go(Routes.dashboard);
      await tester.pumpAndSettle();
      await tester.ensureVisible(f.first);
      await tester.pumpAndSettle();
      final before = loc();
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      final after = loc();
      // ignore: avoid_print
      print('TC-UX-NEW-14 $what: $before → $after');
      return after;
    }

    final twin = await tapOn('twin "Stock နည်းနေသည်" card', find.text('Stock နည်းနေသည်'));
    expect(twin, isNot(Routes.dashboard), reason: 'control: the twin card navigates');
    final debt = await tapOn('"အကြွေးရရန်" card', find.text('အကြွေးရရန်'));
    final row = await tapOn('recent sale row', find.textContaining('#A-1032'));
    final dead = [if (debt == Routes.dashboard) '"အကြွေးရရန်" card', if (row == Routes.dashboard) 'recent sale row'];
    expect(dead, isEmpty, reason: 'look like their tappable twins but do nothing: $dead');
  });

  // TC-UX-NEW-15 (new): a button that cannot act yet must look so (the owner's BUG-40/46 rule: no control that looks ready and
  // does nothing). POS with an empty cart: "ငွေရှင်းမယ်" is disabled (onPressed null) but PrimaryButton only dims when
  // dimWhenDisabled is set, so it is drawn in full colour. The sweep (r14_sweep_test) found the same "silent" state on
  // quick-sale "+ ခြင်းထဲထည့်မယ်" at 0 Ks (enabled, returns) and checkout "−" at quantity 1 (enabled, returns).
  testWidgets('TC-UX-NEW-15 POS "ငွေရှင်းမယ်" with an empty cart looks disabled', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    final btn = find.byWidgetPredicate((w) => w is PrimaryButton && w.label == 'ငွေရှင်းမယ်');
    expect(btn, findsOneWidget);
    final b = tester.widget<PrimaryButton>(btn);
    final dimmed = find.ancestor(of: btn, matching: find.byType(Opacity)).evaluate().any((e) => (e.widget as Opacity).opacity < 1) ||
        find.descendant(of: btn, matching: find.byType(Opacity)).evaluate().any((e) => (e.widget as Opacity).opacity < 1);
    // ignore: avoid_print
    print('TC-UX-NEW-15 empty cart: onPressed=${b.onPressed == null ? 'null (disabled)' : 'set'} dimWhenDisabled=${b.dimWhenDisabled} '
        'dimmed=$dimmed');
    expect(b.onPressed == null && !dimmed, isFalse, reason: 'disabled but drawn exactly like the enabled button');
  });
}
