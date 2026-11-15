// QA round 12b — phone A registers a new grocery shop on the live API (scratch DB) through the Register screens, then
// opens Reports for the brand-new shop: TC-RPT-NEW-1 on a DEBUG build (the release-build half stays MANUAL).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';

import 'qa_harness.dart';

const phoneA = '+959790917051';

void main() {
  qaBinding();

  testWidgets('register shop A on the live API; empty 7-day chart (debug build)', (tester) async {
    final app = await launchApp(tester);
    expect(app.container.read(authControllerProvider).status, AuthStatus.signedOut);

    await tapText(tester, 'ဆိုင်အသစ် စာရင်းသွင်းမယ်');
    await type(tester, field('ဖုန်းနံပါတ်'), '9 790 917 051');
    final before = otpCount(phoneA);
    await tapText(tester, 'ကုဒ်ပို့မယ်');
    final code = await otpFor(tester, phoneA, after: before);
    await waitFor(tester, find.text('အတည်ပြုကုဒ်'));
    await tester.enterText(find.byType(EditableText).last, code);
    await settle(tester);
    await shot(tester, 'reg_A_step1_otp');
    await tapText(tester, 'ဆက်သွားမယ်');

    await type(tester, find.byType(EditableText), 'QA r12b ကုန်စုံ');
    await shot(tester, 'reg_A_step2_shop');
    await tapText(tester, 'ဆက်သွားမယ်');
    await shot(tester, 'reg_A_step3_catalog');
    await tapText(tester, 'ဆက်သွားမယ်');
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('1').last);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, 'reg_A_step4_pin');
    await tapText(tester, 'ဆိုင်ဖွင့်မယ်');
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (app.container.read(authControllerProvider).status != AuthStatus.unlocked) {
      if (DateTime.now().isAfter(end)) {
        await shot(tester, 'reg_A_FAILED');
        fail('not signed in after register');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    await wait(tester, const Duration(seconds: 3));
    await shot(tester, 'reg_A_dashboard');

    // TC-RPT-NEW-1 (debug build): a new shop with no sales.
    app.router.go(Routes.reports);
    await settle(tester);
    await waitFor(tester, find.text('နောက်ဆုံး ၇ ရက်'));
    await tester.ensureVisible(find.text('နောက်ဆုံး ၇ ရက်'));
    await settle(tester);
    expect(find.byKey(const ValueKey('weekChartEmpty')), findsOneWidget);
    expect(find.text('ရောင်းအား မရှိသေးပါ'), findsOneWidget);
    await shot(tester, 'rpt_new1_empty_week_debug');
  });
}
