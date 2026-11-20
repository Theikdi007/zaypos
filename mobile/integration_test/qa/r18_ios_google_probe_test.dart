// QA round 18 (Google Sign-In): probe what Google shows on the iOS simulator after "Google နဲ့ ဝင်မယ်".
// Run with run_qa.sh on a simulator (API on localhost:5076, --dart-define-from-file=google.json via EXTRA_DEFINES).
// The test only taps the Flutter button and waits; the host takes `simctl io screenshot`s of the native Google
// sheet/web page. If Google asks for an email + password the iOS cases are BLOCKED (no credentials in QA).
import 'package:flutter_test/flutter_test.dart';

import 'qa_harness.dart';

void main() {
  qaBinding();

  testWidgets('r18 iOS: tap Google on Login and wait for the native Google page', (tester) async {
    await launchApp(tester);
    await wait(tester, const Duration(seconds: 2));
    expect(find.text('Google နဲ့ ဝင်မယ်'), findsOneWidget);
    await shot(tester, 'r18_ios_probe_login');
    await tapText(tester, 'Google နဲ့ ဝင်မယ်');
    await wait(tester, const Duration(seconds: 45));
    note('after 45 s: shop list=${find.text('ဘယ်ဆိုင်ကို ဝင်မလဲ?').evaluate().isNotEmpty} '
        'PIN=${find.text('ဆိုင်ရဲ့ PIN ထည့်ပါ').evaluate().isNotEmpty} '
        'login=${find.text('Google နဲ့ ဝင်မယ်').evaluate().isNotEmpty}');
  });
}
