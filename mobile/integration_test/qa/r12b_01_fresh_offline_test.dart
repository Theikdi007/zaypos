// QA round 12b — TC-UX-01 on a simulator: the app was deleted (simctl uninstall) and the API is stopped (stand-in for
// airplane mode), then the app is installed and opened → the Login and Register screens render their Myanmar text
// (bundled fonts, no runtime font fetch).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';

import 'qa_harness.dart';

void main() {
  qaBinding();

  testWidgets('TC-UX-01 fresh install, API down: Login + Register render Burmese text', (tester) async {
    final app = await launchApp(tester);
    expect(app.container.read(authControllerProvider).status, AuthStatus.signedOut, reason: 'fresh install');
    expect(find.text('ဆိုင်စာရင်းကို ဖုန်းတစ်လုံးနဲ့ လွယ်လွယ်ကူကူ စီမံပါ'), findsOneWidget);
    expect(find.text('ဝင်မယ်'), findsOneWidget);
    expect(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'), findsOneWidget);
    expect(find.textContaining('အင်တာနက်မရှိလည်း ရောင်းလို့ရပါတယ်'), findsOneWidget);
    // Fonts actually used by the Burmese text: NotoSansMyanmar is bundled (GoogleFonts runtime fetching is off).
    final t = tester.widget<Text>(find.text('ဝင်မယ်'));
    note('login button font: ${t.style?.fontFamily} fallback=${t.style?.fontFamilyFallback}');
    await shot(tester, 'ux01_login_fresh_offline');

    await tapText(tester, 'ဆိုင်အသစ် စာရင်းသွင်းမယ်');
    expect(find.text('အဆင့် 1 / 4'), findsOneWidget);
    await shot(tester, 'ux01_register_step1_offline');

    // "ကုဒ်ပို့မယ်" with the API down → a Burmese network message, no crash.
    await tester.enterText(find.byType(EditableText).first, '9 790 917 051');
    await tapText(tester, 'ကုဒ်ပို့မယ်');
    await wait(tester, const Duration(seconds: 3));
    await shot(tester, 'ux01_register_send_code_offline');
    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => s.isNotEmpty).toList();
    note('register texts after send (offline): $texts');
  });
}
