// QA round 13 — BUG-41 / TC-AUTH-NEW-3 on the iOS simulator against the live API (scratch DB). The Myanmar keyboard is
// simulated by injecting Myanmar digits (as a paste would); the real keyboard stays MANUAL.
// QA_STEP=login (fresh install): Register → phone and SMS code in Myanmar digits → the server accepts the code (step 2
//   opens); then Login → phone and PIN in Myanmar digits → shop A opens.
// QA_STEP=reset (app locked): "PIN မေ့နေပါသလား?" → phone, SMS code and both new-PIN fields in Myanmar digits → signed in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/session.dart';

import 'qa_harness.dart';

const step = String.fromEnvironment('QA_STEP', defaultValue: 'login');
const phoneA = '+959790917051';
const phoneNew = '+959790917061';
const mm = ['၀', '၁', '၂', '၃', '၄', '၅', '၆', '၇', '၈', '၉'];
String toMm(String s) => s.split('').map((c) => RegExp(r'\d').hasMatch(c) ? mm[int.parse(c)] : c).join();

Future<void> waitUnlocked(WidgetTester tester, QaApp app, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (app.container.read(authControllerProvider).status != AuthStatus.unlocked) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'r13_auth_FAILED_$what');
      fail('$what: not signed in; status=${app.container.read(authControllerProvider).status}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  qaBinding();

  testWidgets('BUG-41 Myanmar digits in the auth fields, live ($step)', (tester) async {
    final app = await launchApp(tester);

    if (step == 'login') {
      expect(app.container.read(authControllerProvider).status, AuthStatus.signedOut, reason: 'fresh install');
      // ---------------------------------------------------------------- Register: phone + SMS code
      await tapText(tester, 'ဆိုင်အသစ် စာရင်းသွင်းမယ်');
      final phone = find.byType(EditableText).first;
      await type(tester, phone, toMm('09 790 917 061'));
      final kept = fieldText(tester, phone);
      note('register phone after injecting "${toMm('09 790 917 061')}": "$kept"');
      expect(kept, '09 790 917 061');
      final before = otpCount(phoneNew);
      await tapText(tester, 'ကုဒ်ပို့မယ်');
      final code = await otpFor(tester, phoneNew, after: before);
      note('server sent an OTP to $phoneNew (the Myanmar-digit number arrived as ASCII)');
      await settle(tester);
      final otp = find.byType(EditableText).last;
      await tester.enterText(otp, toMm(code));
      await settle(tester);
      note('register OTP after injecting "${toMm(code)}": "${fieldText(tester, otp)}"');
      expect(fieldText(tester, otp), code);
      await shot(tester, 'r13_auth41_register_otp_myanmar');
      // The server checks the register code only at the final step (RegisterScreen._next); here only "6 digits kept,
      // step 2 opens" is checked. A server-checked Myanmar-digit OTP is proven by the reset step below.
      await tapText(tester, 'ဆက်သွားမယ်');
      await waitFor(tester, field('ဆိုင်အမည်'), timeout: const Duration(seconds: 20), why: 'register step 2 after the code');
      note('register: 6-digit code accepted locally (shop-name step opened)');
      await shot(tester, 'r13_auth41_register_step2');

      // ---------------------------------------------------------------- Login: phone + PIN
      app.router.go(Routes.login);
      await settle(tester);
      await type(tester, field('ဖုန်းနံပါတ်'), toMm('09 790 917 051'));
      await type(tester, field('PIN နံပါတ်'), toMm('222222'));
      note('login phone "${fieldText(tester, field('ဖုန်းနံပါတ်'))}", PIN length ${fieldText(tester, field('PIN နံပါတ်')).length} '
          'digitsOnly=${RegExp(r'^\d{6}$').hasMatch(fieldText(tester, field('PIN နံပါတ်')))}');
      expect(fieldText(tester, field('ဖုန်းနံပါတ်')), '09 790 917 051');
      expect(fieldText(tester, field('PIN နံပါတ်')), '222222');
      await shot(tester, 'r13_auth41_login_myanmar');
      await tapText(tester, 'ဝင်မယ်');
      await waitUnlocked(tester, app, 'login');
      await wait(tester, const Duration(seconds: 6));
      note('login with Myanmar digits: shop="${app.container.read(sessionProvider).shopName}"');
      expect(app.container.read(sessionProvider).shopName, 'QA r12b ကုန်စုံ');
      await shot(tester, 'r13_auth41_login_dashboard');
      return;
    }

    // ---------------------------------------------------------------- step == 'reset' (locked)
    await waitFor(tester, find.text('PIN နံပါတ် ထည့်ပါ'));
    await tapText(tester, 'PIN မေ့နေပါသလား?');
    await waitFor(tester, find.text('PIN အသစ် သတ်မှတ်မယ်'));
    await type(tester, field('ဖုန်းနံပါတ်'), toMm('09 790 917 051'));
    note('reset phone: "${fieldText(tester, field('ဖုန်းနံပါတ်'))}"');
    expect(fieldText(tester, field('ဖုန်းနံပါတ်')), '09 790 917 051');
    final before = otpCount(phoneA);
    await tapText(tester, 'ကုဒ်ပို့မယ်');
    final code = await otpFor(tester, phoneA, after: before);
    await waitFor(tester, field('OTP ကုဒ်'));
    await type(tester, field('OTP ကုဒ်'), toMm(code));
    await type(tester, field('PIN အသစ် (၆ လုံး)'), toMm('222222'));
    await type(tester, field('PIN အသစ် ထပ်ရိုက်ပါ'), toMm('222222'));
    final kept = [
      fieldText(tester, field('OTP ကုဒ်')),
      fieldText(tester, field('PIN အသစ် (၆ လုံး)')),
      fieldText(tester, field('PIN အသစ် ထပ်ရိုက်ပါ')),
    ];
    note('reset OTP/PIN/PIN-again after injecting Myanmar digits: $kept (code $code)');
    await shot(tester, 'r13_auth41_reset_myanmar');
    expect(kept, [code, '222222', '222222']);
    await tapText(tester, 'PIN အသစ် သိမ်းမယ်');
    await waitUnlocked(tester, app, 'reset');
    await wait(tester, const Duration(seconds: 3));
    note('reset with Myanmar digits: shop="${app.container.read(sessionProvider).shopName}"');
    expect(app.container.read(sessionProvider).shopName, 'QA r12b ကုန်စုံ');
    await shot(tester, 'r13_auth41_reset_dashboard');
  });
}
