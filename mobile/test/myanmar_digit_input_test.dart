// BUG-41: Login / Register / PIN-reset fields turn Myanmar digits ၀-၉ (typed or pasted) into 0-9 instead of dropping them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/digit_input.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/auth/presentation/pin_reset_screen.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'helpers.dart';

TextEditingValue _apply(List<TextInputFormatter> fs, String text, {TextEditingValue old = TextEditingValue.empty}) {
  var v = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  for (final f in fs) {
    v = f.formatEditUpdate(old, v);
  }
  return v;
}

void main() {
  group('formatters', () {
    test('every Myanmar digit maps to its ASCII digit', () {
      expect(MyanmarDigitsToAscii.convert('၀၁၂၃၄၅၆၇၈၉'), '0123456789');
      expect(MyanmarDigitsToAscii.convert('၀၉ ၇၉၀ ၉၁၇ ၀၅၁'), '09 790 917 051');
      expect(MyanmarDigitsToAscii.convert('ab12'), 'ab12');
    });

    test('phone: pasted Myanmar number is kept (QA input "၀၉ ၇၉၀ ၉၁၇ ၀၅၁"), mixed digits too', () {
      expect(_apply(phoneInput(), '၀၉ ၇၉၀ ၉၁၇ ၀၅၁').text, '09 790 917 051');
      expect(_apply(phoneInput(), '9 ၇၉၀ 917-051').text, '9 790 917051', reason: 'non-digits still dropped');
    });

    test('OTP / PIN: Myanmar digits kept, 6 at most, cursor stays at the end', () {
      expect(_apply(digitInput(maxLength: 6), '၀၀၇၄၈၀').text, '007480');
      expect(_apply(digitInput(maxLength: 6), '၂၂၂၂၂၂').text, '222222');
      expect(_apply(digitInput(maxLength: 6), '၁၂၃၄၅၆၇၈').text, '123456');
      final v = _apply(digitInput(maxLength: 6), '12၃');
      expect(v.text, '123');
      expect(v.selection, const TextSelection.collapsed(offset: 3));
    });

    test('a Myanmar digit typed in the middle keeps the cursor after it', () {
      const old = TextEditingValue(text: '1256', selection: TextSelection.collapsed(offset: 2));
      final v = const MyanmarDigitsToAscii().formatEditUpdate(
          old, const TextEditingValue(text: '12၃56', selection: TextSelection.collapsed(offset: 3)));
      expect(v.text, '12356');
      expect(v.selection, const TextSelection.collapsed(offset: 3));
    });
  });

  group('screens', () {
    setUpAll(loadAppFonts);
    late AppDatabase db;
    late FakeAuthApi api;
    setUp(() {
      db = memoryDb();
      api = FakeAuthApi();
    });
    tearDown(() => db.close());

    Future<ProviderContainer> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        ...fakeOverrides(boot: BootState(deviceId: newId())),
        appDatabaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        authApiProvider.overrideWithValue(api),
        otpEnabledProvider.overrideWithValue(true), // the SMS OTP screens (AUTH_OTP_ENABLED)
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Finder input(int i) => find.byType(EditableText).at(i);
    String textOf(WidgetTester tester, int i) => (tester.widget<EditableText>(input(i))).controller.text;

    testWidgets('Login: Myanmar phone and PIN reach the sign-in as 0-9', (tester) async {
      await boot(tester);
      await tester.enterText(input(0), '၉ ၇၁၂၃ ၄၅၆၇');
      await tester.enterText(input(1), '၁၂၃၄၅၆');
      expect(textOf(tester, 0), '9 7123 4567');
      expect(textOf(tester, 1), '123456');
      await tester.tap(find.text('ဝင်မယ်'));
      await settle(tester);
      expect(api.calls.first, 'login:+95971234567');
    });

    testWidgets('Register: Myanmar phone and SMS code are kept', (tester) async {
      await boot(tester);
      await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
      await tester.pumpAndSettle();
      await tester.enterText(input(0), '၀၉ ၇၁၂၃ ၄၅၆၇');
      expect(textOf(tester, 0), '09 7123 4567');
      await tester.tap(find.text('ကုဒ်ပို့မယ်'));
      await settle(tester);
      expect(api.calls, ['otp:register:+95971234567']);
      await tester.enterText(input(1), '၄၈၂၉၁၃');
      expect(textOf(tester, 1), '482913');
    });

    testWidgets('PIN reset: Myanmar phone, SMS code and new PIN (QA\'s inputs) are kept and used', (tester) async {
      await boot(tester);
      await tester.tap(find.text('PIN မေ့နေပါသလား?'));
      await tester.pumpAndSettle();
      expect(find.byType(PinResetScreen), findsOneWidget);

      await tester.enterText(input(0), '၀၉ ၇၉၀ ၉၁၇ ၀၅၁');
      expect(textOf(tester, 0), '09 790 917 051');
      await tester.tap(find.text('ကုဒ်ပို့မယ်'));
      await settle(tester);
      expect(api.calls, ['otp:reset:+959790917051']);

      await tester.enterText(input(1), '၀၀၇၄၈၀');
      await tester.enterText(input(2), '၂၂၂၂၂၂');
      await tester.enterText(input(3), '၂၂၂၂၂၂');
      expect([textOf(tester, 1), textOf(tester, 2), textOf(tester, 3)], ['007480', '222222', '222222']);
      await tester.tap(find.text('PIN အသစ် သိမ်းမယ်'));
      await settle(tester);
      expect(api.calls.sublist(1, 3), ['reset:+959790917051', 'login:+959790917051']);
    });
  });
}
