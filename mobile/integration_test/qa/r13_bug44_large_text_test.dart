// QA round 13 — BUG-44 / TC-UX-03 on the iOS simulator: phone B (iPhone 17e, 390×844 pt) at the largest STANDARD text size
// (simctl content_size extra-extra-extra-large, ×1.35; no accessibility sizes). Real app, real fonts, grocery shop A.
// POS opens on "အမြန်ရောင်း": no layout error; the add button scrolls fully clear of the cart bar and a tap there adds the
// amount; the cart bar sits above the home indicator; "ပစ္စည်းများ": the last product row scrolls fully clear of the cart bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';

import 'qa_harness.dart';

const font = String.fromEnvironment('QA_FONT', defaultValue: 'xxxl');

void main() {
  qaBinding();

  testWidgets('BUG-44 POS at the largest standard text size ($font)', (tester) async {
    await hostCmd(tester, 'font_$font');
    final problems = <String>[];
    final old = FlutterError.onError;
    try {
      final app = await launchApp(tester);
      FlutterError.onError = (d) => problems.add('${d.exceptionAsString().split('\n').first} @ ${app.router.location}');
      await unlockIfLocked(tester, app, pin: '222222');
      final mq = MediaQuery.of(tester.element(find.byType(Scaffold).first));
      final screenH = mq.size.height;
      final inset = mq.padding.bottom;
      note('[$font] screen ${mq.size.width}x$screenH pt, bottom inset $inset, textScaler(14)/14=${mq.textScaler.scale(14) / 14}');
      app.container.read(cartProvider.notifier).clear();

      app.router.go(Routes.pos);
      await settle(tester);
      await wait(tester, const Duration(seconds: 1));
      Rect bar() => tester.getRect(find.ancestor(of: find.text('ငွေရှင်းမယ်'), matching: find.byType(Positioned)).first);

      // ---------------------------------------------------------------- "အမြန်ရောင်း"
      if (find.text('+ ခြင်းထဲထည့်မယ်').evaluate().isEmpty) await tapText(tester, 'အမြန်ရောင်း');
      await shot(tester, 'r13_ux44_quick_sale_top');
      note('[$font] cart bar $bar, its bottom gap to the screen edge ${(screenH - bar().bottom).toStringAsFixed(1)} (inset $inset)');
      expect(bar().bottom, lessThanOrEqualTo(screenH - inset), reason: 'cart bar above the home indicator');
      for (final tab in ['ပစ္စည်းများ', 'အမြန်ရောင်း']) {
        final r = tester.getRect(find.text(tab));
        expect(r.top >= 0 && r.bottom <= screenH, isTrue, reason: '$tab tab on screen: $r');
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await settle(tester);
      final button = tester.getRect(find.ancestor(of: find.text('+ ခြင်းထဲထည့်မယ်'), matching: find.byType(InkWell)).first);
      note('[$font] quick sale scrolled to the end: add button $button, cart bar top ${bar().top}');
      await shot(tester, 'r13_ux44_quick_sale_end');
      expect(button.bottom, lessThanOrEqualTo(bar().top), reason: 'add button fully above the cart bar');
      // Type 500 on the quick-sale keypad and tap the button (real hit test at its centre).
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await settle(tester);
      for (final k in ['5', '00']) {
        await tester.ensureVisible(find.text(k).first);
        await tester.tap(find.text(k).first);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await settle(tester);
      await tester.tap(find.text('+ ခြင်းထဲထည့်မယ်'));
      await settle(tester);
      final quick = app.container.read(cartProvider).quickLines.map((l) => l.price).toList();
      note('[$font] after tapping the add button: quick lines $quick');
      await shot(tester, 'r13_ux44_quick_sale_added');
      expect(quick, [500]);

      // ---------------------------------------------------------------- "ပစ္စည်းများ"
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await settle(tester);
      await tapText(tester, 'ပစ္စည်းများ');
      await wait(tester, const Duration(milliseconds: 500));
      await shot(tester, 'r13_ux44_products_top');
      await tester.drag(find.byType(GridView).first, const Offset(0, -20000));
      await settle(tester);
      await tester.drag(find.byType(GridView).first, const Offset(0, -20000));
      await settle(tester);
      final grid = tester.getRect(find.byType(GridView).first);
      final tiles = find.descendant(of: find.byType(GridView).first, matching: find.byType(InkWell));
      final lastBottom = tiles.evaluate().map((e) => tester.getRect(find.byWidget(e.widget).first).bottom).fold<double>(0, (a, b) => b > a ? b : a);
      note('[$font] grid $grid, ${tiles.evaluate().length} tiles built, lowest tile bottom $lastBottom, cart bar top ${bar().top}');
      await shot(tester, 'r13_ux44_products_end');
      expect(lastBottom, lessThanOrEqualTo(bar().top), reason: 'last product row fully above the cart bar');
      app.container.read(cartProvider.notifier).clear();
      await settle(tester);
    } finally {
      FlutterError.onError = old;
      await hostCmd(tester, 'font_default');
    }
    note('[$font] layout problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    expect(problems, isEmpty);
  });
}
