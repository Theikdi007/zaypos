// QA round 12b — phone B (iPhone 17e, the smallest iPhone the iOS 27 simulator offers) with the LARGEST Dynamic Type
// (simctl ui content_size accessibility-extra-extra-extra-large).
// TC-PIN-05 (simulator half): a wrong PIN 3× → time from the 6th digit to the error, then the right PIN.
// TC-UX-03: every screen in the list is opened; any "RenderFlex overflowed" / layout error is collected (and fails the test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/presentation/widgets/auth_message.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';

import 'qa_harness.dart';

/// xxxl = the largest size in Settings without "Larger Accessibility Sizes"; ax5 = the largest accessibility size.
const font = String.fromEnvironment('QA_FONT', defaultValue: 'xxxl');
const mmDigit = ['၀', '၁', '၂', '၃', '၄', '၅', '၆', '၇', '၈', '၉'];
const longName = 'QA r12b ဒေါ်ခင်မြင့်မြင့်သန်း (ရွှေပြည်သာ ဈေးကြီး အရှေ့ဘက်)';

void main() {
  qaBinding();

  testWidgets('TC-PIN-05 + TC-UX-03 on the small phone with the largest font', (tester) async {
    await hostCmd(tester, 'font_$font');
    final app = await launchApp(tester);
    final c = app.container;
    final mq = MediaQuery.of(tester.element(find.byType(Scaffold).first));
    note(
      'screen ${mq.size.width}x${mq.size.height} pt, textScaler(14)=${mq.textScaler.scale(14)} (×${mq.textScaler.scale(14) / 14})',
    );

    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      problems.add('${s.split('\n').first} @ ${app.router.location}');
    };

    try {
      // ---------------------------------------------------------------- TC-PIN-05 (wrong PIN 3×)
      await waitFor(tester, find.text('PIN နံပါတ် ထည့်ပါ'));
      await shot(tester, '${font}_ux03_unlock');
      final zero = tester.getRect(find.text('0').last);
      note(
        '[$font] unlock screen at open: keypad "0" key at y=${zero.top.round()}..${zero.bottom.round()}, '
        'screen height ${mq.size.height.round()} → ${zero.bottom <= mq.size.height ? 'visible' : 'below the screen (scroll needed)'}',
      );
      String? message() {
        final m = find.descendant(of: find.byType(AuthMessage), matching: find.byType(Text));
        return m.evaluate().isEmpty ? null : (m.evaluate().first.widget as Text).data;
      }

      for (var attempt = 1; attempt <= 3; attempt++) {
        final before = message();
        final sw = Stopwatch();
        for (var i = 0; i < 6; i++) {
          await tester.ensureVisible(find.text('9').last);
          await tester.pump(const Duration(milliseconds: 30));
          if (i == 5) sw.start();
          await tester.tap(find.text('9').last);
          await tester.pump(const Duration(milliseconds: 30));
        }
        // The tries-left count changes with every wrong PIN, so a new message text = this attempt's answer.
        while ((message() == null || message() == before) && sw.elapsed < const Duration(seconds: 20)) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        sw.stop();
        final msg = find.descendant(of: find.byType(AuthMessage), matching: find.byType(Text));
        note(
          '[$font] wrong PIN #$attempt: message for this attempt after ${sw.elapsedMilliseconds} ms: '
          '"${msg.evaluate().isEmpty ? '-' : (msg.evaluate().first.widget as Text).data}"',
        );
        if (attempt == 1) {
          final key2 = tester.getRect(find.text('0').last);
          note(
            '[$font] keypad "0" key at y=${key2.top.round()}..${key2.bottom.round()} (screen height ${mq.size.height.round()}) '
            'after scrolling it into view',
          );
        }
        if (attempt == 3) await shot(tester, '${font}_pin05_wrong_pin_3x');
      }
      await unlockIfLocked(tester, app, pin: '222222');

      // ---------------------------------------------------------------- TC-UX-03 screens
      Future<void> visit(String route, String name, {bool scroll = true}) async {
        app.router.go(route);
        await settle(tester);
        await wait(tester, const Duration(milliseconds: 800));
        await shot(tester, '${font}_ux03_$name');
        if (scroll && find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -600), warnIfMissed: false);
          await settle(tester);
          await shot(tester, '${font}_ux03_${name}_scrolled');
        }
      }

      await visit(Routes.dashboard, 'dashboard');
      await visit(Routes.pos, 'pos');
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
      await tapText(tester, 'QA r12b ဆပ်ပြာ');
      await tapText(tester, 'ငွေရှင်းမယ်');
      await shot(tester, '${font}_ux03_checkout');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600), warnIfMissed: false);
      await settle(tester);
      await shot(tester, '${font}_ux03_checkout_scrolled');
      await visit(Routes.products, 'products');
      await visit(Routes.reports, 'reports');
      await visit(Routes.sales, 'sales');

      // Customer with a long name, an opening debt and a limit → the edit form shows "လက်ရှိ အကြွေး" next to the limit.
      app.router.go(Routes.addCustomer);
      await settle(tester);
      await type(tester, field('အမည်'), longName);
      await type(tester, field('ဖုန်းနံပါတ်'), '09 790 011 077');
      await type(tester, field('အကြွေး ကန့်သတ်ချက်'), '100000');
      await type(tester, field('ယခင်အကြွေး'), '45000');
      await shot(tester, '${font}_ux03_add_customer');
      await tapText(tester, 'သိမ်းမယ်', last: true);
      await wait(tester, const Duration(seconds: 1));
      if (find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ').evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
        await settle(tester);
      }
      c.listen(customersProvider, (_, _) {});
      await wait(tester, const Duration(seconds: 1));
      final cust = (c.read(customersProvider).value ?? const []).firstWhere((x) => x.name == longName);
      await visit(Routes.customer(cust.id), 'customer_debt');
      await visit(Routes.editCustomer(cust.id), 'edit_customer_current_balance');
      note('edit form shows "လက်ရှိ အကြွေး": ${find.byKey(const ValueKey('currentBalance')).evaluate().isNotEmpty}');

      // Duplicate-phone dialog with the long name.
      app.router.go(Routes.addCustomer);
      await settle(tester);
      await type(tester, field('အမည်'), 'QA r12b ဒုတိယ');
      await type(tester, field('ဖုန်းနံပါတ်'), '09790011077');
      await tapText(tester, 'သိမ်းမယ်', last: true);
      await wait(tester, const Duration(seconds: 1));
      await shot(tester, '${font}_ux03_duplicate_phone_dialog_long_name');
      if (find.byKey(const ValueKey('duplicatePhoneCancel')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
        await settle(tester);
      }

      await visit(Routes.settingsFeatures, 'settings');
      await visit(Routes.syncReview, 'sync_review');
      if (find.textContaining('ပြီးသွားတဲ့ ကိစ္စများ').evaluate().isNotEmpty) {
        await tapText(
          tester,
          find.textContaining('ပြီးသွားတဲ့ ကိစ္စများ').evaluate().first.widget is Text
              ? (find.textContaining('ပြီးသွားတဲ့ ကိစ္စများ').evaluate().first.widget as Text).data!
              : 'ပြီးသွားတဲ့ ကိစ္စများ',
        );
        await shot(tester, '${font}_ux03_sync_review_resolved');
      }
      await visit(Routes.devices, 'devices');
    } finally {
      FlutterError.onError = old;
      await hostCmd(tester, 'font_default');
    }
    note('[$font] layout problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    expect(problems, isEmpty);
  });
}
