// QA round 12b — phone B (second simulator, fresh install): TC-AUTH-NEW-3 on the screens.
// 1. Sign in typing the number with spaces "09 790 917 051" → the same shop as phone A opens, A's data is pulled.
// 2. Restart → locked → "PIN မေ့နေပါသလား?" → PIN reset. The Myanmar keyboard is simulated by injecting Myanmar digits into
//    the phone / OTP / PIN fields; what the fields keep is recorded. The reset is then finished (ASCII where needed) with
//    the new PIN 222222, and phone B opens the same shop again.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';

import 'qa_harness.dart';

const phoneA = '+959790917051';
const mm = ['၀', '၁', '၂', '၃', '၄', '၅', '၆', '၇', '၈', '၉'];
String toMm(String s) => s.split('').map((c) => RegExp(r'\d').hasMatch(c) ? mm[int.parse(c)] : c).join();

Future<void> waitUnlocked(WidgetTester tester, QaApp app, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (app.container.read(authControllerProvider).status != AuthStatus.unlocked) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'auth3_FAILED_$what');
      fail('$what: not signed in; status=${app.container.read(authControllerProvider).status}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  qaBinding();

  testWidgets('B: sign in with spaces, then PIN reset typed in Myanmar digits', (tester) async {
    final app = await launchApp(tester);
    final step = const String.fromEnvironment('QA_STEP', defaultValue: 'signin');

    if (step == 'signin') {
      expect(app.container.read(authControllerProvider).status, AuthStatus.signedOut, reason: 'fresh install on B');
      await type(tester, field('ဖုန်းနံပါတ်'), '09 790 917 051');
      note('login phone field keeps: "${fieldText(tester, field('ဖုန်းနံပါတ်'))}"');
      await type(tester, field('PIN နံပါတ်'), '111111');
      await shot(tester, 'auth3_B_login_spaces');
      await tapText(tester, 'ဝင်မယ်');
      await waitUnlocked(tester, app, 'login');
      await wait(tester, const Duration(seconds: 8)); // first sync pulls A's shop
      final s = app.container.read(sessionProvider);
      note('B signed in: shop="${s.shopName}" ');
      expect(s.shopName, 'QA r12b ကုန်စုံ');
      await shot(tester, 'auth3_B_dashboard_after_login');
      app.router.go(Routes.products);
      await settle(tester);
      await wait(tester, const Duration(seconds: 2));
      final names = (app.container.read(productsProvider).value ?? const []).map((p) => p.name).toList();
      note('B products after first sync: $names');
      await shot(tester, 'auth3_B_products_pulled');
      return;
    }

    // step == 'reset': the app restarted, so it is locked.
    await waitFor(tester, find.text('PIN နံပါတ် ထည့်ပါ'));
    await tapText(tester, 'PIN မေ့နေပါသလား?');
    await waitFor(tester, find.text('PIN အသစ် သတ်မှတ်မယ်'));
    final phoneField = field('ဖုန်းနံပါတ်');
    await type(tester, phoneField, toMm('09 790 917 051'));
    final keptMm = fieldText(tester, phoneField);
    note('reset phone field after injecting Myanmar digits "${toMm('09 790 917 051')}": keeps "$keptMm"');
    await shot(tester, 'auth3_B_reset_phone_myanmar_digits');
    if (keptMm.replaceAll(' ', '').length < 9) {
      await type(tester, phoneField, '09 790 917 051');
      note('phone re-typed in ASCII to continue');
    }
    final before = otpCount(phoneA);
    await tapText(tester, 'ကုဒ်ပို့မယ်');
    final code = await otpFor(tester, phoneA, after: before);
    await waitFor(tester, field('OTP ကုဒ်'));
    await type(tester, field('OTP ကုဒ်'), toMm(code));
    final otpKept = fieldText(tester, field('OTP ကုဒ်'));
    note('OTP field after injecting "${toMm(code)}": keeps "$otpKept"');
    await type(tester, field('PIN အသစ် (၆ လုံး)'), toMm('222222'));
    note('new-PIN field after injecting "${toMm('222222')}": keeps "${fieldText(tester, field('PIN အသစ် (၆ လုံး)'))}"');
    await shot(tester, 'auth3_B_reset_otp_pin_myanmar_digits');
    if (otpKept != code) await type(tester, field('OTP ကုဒ်'), code);
    await type(tester, field('PIN အသစ် (၆ လုံး)'), '222222');
    await type(tester, field('PIN အသစ် ထပ်ရိုက်ပါ'), '222222');
    await tapText(tester, 'PIN အသစ် သိမ်းမယ်');
    await waitUnlocked(tester, app, 'reset');
    await wait(tester, const Duration(seconds: 3));
    note('B after reset: shop="${app.container.read(sessionProvider).shopName}"');
    expect(app.container.read(sessionProvider).shopName, 'QA r12b ကုန်စုံ');
    await shot(tester, 'auth3_B_after_reset');
  });
}
