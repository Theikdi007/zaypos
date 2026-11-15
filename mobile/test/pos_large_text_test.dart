// BUG-44: at the largest standard iOS text size (×1.35, "Larger Accessibility Sizes" off) on a 390×844 phone,
// POS has no overflow, the tabs are fully visible, and "+ ခြင်းထဲထည့်မယ်" can be scrolled fully clear of the cart bar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/widgets/product_tile.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  // iOS "Larger Text" slider at the maximum without accessibility sizes, and the step below it.
  for (final scale in const [1.35, 1.24, 1.0]) {
    // QA's phone (iPhone 17e). Narrower screens have other large-text issues outside POS (dashboard, bottom nav).
    for (final size in const [Size(390, 844)]) {
      testWidgets('POS quick sale at text ×$scale on $size: no overflow, tabs and add button clear of the cart bar',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final c = makeContainer();
        addTearDown(c.dispose);
        c.read(shopTemplateProvider.notifier).select('grocery');
        await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
        await tester.pumpAndSettle();
        c.read(appRouterProvider).go('/pos');
        await tester.pumpAndSettle();

        // Opens on "အမြန်ရောင်း" (the case QA hit).
        expect(find.text('+ ခြင်းထဲထည့်မယ်'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'layout problems on "အမြန်ရောင်း"');

        final screen = Offset.zero & size;
        for (final tab in ['ပစ္စည်းများ', 'အမြန်ရောင်း']) {
          final r = tester.getRect(find.text(tab));
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight), isTrue, reason: '$tab tab on screen: $r');
        }

        // Scroll to the end: the whole add button must be above the cart bar.
        await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        final button = tester.getRect(find.ancestor(of: find.text('+ ခြင်းထဲထည့်မယ်'), matching: find.byType(InkWell)).first);
        final bar = tester.getRect(find.ancestor(of: find.text('ငွေရှင်းမယ်'), matching: find.byType(Container)).last);
        expect(button.bottom, lessThanOrEqualTo(bar.top), reason: 'add button $button vs cart bar $bar');

        // Tapping it really adds the amount.
        await tester.tap(find.text('5').first);
        await tester.tap(find.text('00').first);
        await tester.pump();
        await tester.tap(find.text('+ ခြင်းထဲထည့်မယ်'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ထည့်ပြီး: 500 Ks'), findsOneWidget);

        // The products tab too.
        await tester.tap(find.text('ပစ္စည်းများ'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'layout problems after switching tabs');
      });
    }
  }

  // The 78 px overflow QA saw: a product name that wraps in the fixed 160 px grid row.
  for (final scale in const [1.0, 1.24, 1.35]) {
    testWidgets('product tile with a long name fits its grid row at text ×$scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => GridView(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: ProductTile.extent(MediaQuery.textScalerOf(context)),
            ),
            children: [
              for (final name in ['QA r12b ဆပ်ပြာ', 'ဒေါ်ခင်မြင့် ဆပ်ပြာ အကြီး ရွှေပြည်သာ (၁၀ လုံးတွဲ)', 'ရေ'])
                ProductTile(
                  name: name,
                  initial: 'ဆ',
                  tint: const Color(0xFFE0F2F1),
                  price: 1250000,
                  stockLabel: 'Stock 120',
                  onTap: () {},
                ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scale == 1.0) expect(ProductTile.extent(MediaQuery.textScalerOf(tester.element(find.byType(GridView)))), 160);
    });
  }
}
