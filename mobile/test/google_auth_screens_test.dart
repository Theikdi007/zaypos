// Google Sign-In screens (docs/backend/auth-google.md §5), default flow (AUTH_OTP_ENABLED off).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/widgets/numeric_keypad.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/auth/presentation/google_shop_screen.dart';
import 'package:zaypos_app/features/auth/presentation/login_screen.dart';
import 'package:zaypos_app/features/auth/presentation/register_screen.dart';
import 'package:zaypos_app/features/auth/presentation/unlock_screen.dart';
import 'package:zaypos_app/features/sync/presentation/first_sync_screen.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  late AppDatabase db;
  late FakeAuthApi api;
  late FakeGoogleAuth google;
  late MemorySecureStore store;
  setUp(() {
    db = memoryDb();
    api = FakeAuthApi();
    google = FakeGoogleAuth();
    store = MemorySecureStore();
  });
  tearDown(() => db.close());

  Future<ProviderContainer> boot(WidgetTester tester, {BootState? state, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeOverrides(boot: state ?? BootState(deviceId: newId())),
      appDatabaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(api),
      googleAuthProvider.overrideWithValue(google),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      isReleaseBuildProvider.overrideWithValue(false),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> settle(WidgetTester tester, {bool animating = false}) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      if (animating) {
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await tester.pumpAndSettle();
      }
    }
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.descendant(of: find.byType(NumericKeypad), matching: find.text(d)).first);
      await tester.pump();
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
  }

  testWidgets('Login shows Google only: no phone field, no SMS code anywhere', (tester) async {
    await boot(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Google နဲ့ ဝင်မယ်'), findsOneWidget);
    expect(find.text('ဖုန်းနံပါတ်'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(find.textContaining('OTP'), findsNothing);
    expect(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'), findsOneWidget);
  });

  testWidgets('new phone: Google → choose one of two shops → PIN → first download, signed in to THAT shop', (tester) async {
    api.googleShopList = const [
      GoogleShop(tenantId: 'shop-1', name: 'ရွှေဝါ', templateId: 'grocery'),
      GoogleShop(tenantId: 'shop-2', name: 'မြဆေးဆိုင်', templateId: 'pharmacy'),
    ];
    final c = await boot(tester);

    await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
    await settle(tester);
    expect(find.byType(GoogleShopScreen), findsOneWidget);
    expect(find.text('owner@gmail.com'), findsOneWidget);
    expect(find.text('ဘယ်ဆိုင်ကို ဝင်မလဲ?'), findsOneWidget);

    await tester.tap(find.text('မြဆေးဆိုင်'));
    await tester.pumpAndSettle();
    expect(find.text('ဆိုင်ရဲ့ PIN ထည့်ပါ'), findsOneWidget);
    await typePin(tester, '123456');
    await tapText(tester, 'ဝင်မယ်');
    await settle(tester, animating: true);

    expect(api.calls, ['google:shops', 'google:signIn:shop-2:123456']);
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(c.read(sessionProvider).tenantId, 'shop-2');
    expect(find.byType(FirstSyncScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong PIN shows the server message in Burmese, clears the dots and stays', (tester) async {
    api.googleShopList = const [GoogleShop(tenantId: 'shop-1', name: 'ရွှေဝါ', templateId: 'grocery')];
    await boot(tester);
    await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
    await settle(tester);
    expect(find.text('ဆိုင်ရဲ့ PIN ထည့်ပါ'), findsOneWidget, reason: 'one shop: chosen for you');

    api.nextError = const ApiError(401, 'invalid_credentials');
    await typePin(tester, '000000');
    await tapText(tester, 'ဝင်မယ်');
    await settle(tester);

    expect(find.text(apiErrorMessage('invalid_credentials')), findsOneWidget);
    expect(find.byType(GoogleShopScreen), findsOneWidget);

    // The dots were cleared: a fresh 6 digits is exactly what goes out next.
    await typePin(tester, '123456');
    await tapText(tester, 'ဝင်မယ်');
    await settle(tester, animating: true);
    expect(api.calls.last, 'google:signIn:shop-1:123456');
  });

  testWidgets('cancelled / no account / offline on the picker: Burmese message on Login, nothing else happens',
      (tester) async {
    await boot(tester);
    for (final f in const [
      AuthFailure('google_cancelled', GoogleMessages.cancelled),
      AuthFailure('google_no_account', GoogleMessages.noAccount),
      AuthFailure('google_play_services', GoogleMessages.playServices),
      AuthFailure('network', GoogleMessages.offline),
    ]) {
      google.nextError = f;
      await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
      await settle(tester);
      expect(find.text(f.message), findsOneWidget, reason: f.code);
      expect(find.byType(LoginScreen), findsOneWidget);
    }
    expect(api.calls, isEmpty);
  });

  testWidgets('no shop yet → "ဆိုင်အသစ် ဖွင့်မယ်" → register with the Google step done: name, owner phone, PIN',
      (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
    await settle(tester);
    expect(find.text('ဒီ Google အကောင့်မှာ ဆိုင် မရှိသေးပါ'), findsOneWidget);

    await tapText(tester, 'ဆိုင်အသစ် ဖွင့်မယ်');
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('owner@gmail.com'), findsOneWidget, reason: 'step 1 shows the picked account');
    await tapText(tester, 'ဆက်သွားမယ်');
    await tester.pumpAndSettle();

    // Step 2: the owner phone is required (a contact, not verified).
    await tester.enterText(find.byType(EditableText).at(0), 'ရွှေဝါ');
    await tapText(tester, 'ဆက်သွားမယ်');
    await tester.pumpAndSettle();
    expect(find.text(AuthMessages.badOwnerPhone), findsOneWidget);
    expect(find.text('ဆက်သွယ်ဖို့ပဲ သုံးပါမယ် (SMS မပို့ပါ)'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).at(1), '9 790 917 041');
    await tapText(tester, 'ဆက်သွားမယ်');
    await tester.pumpAndSettle();
    await tapText(tester, 'ဆက်သွားမယ်'); // step 3: catalog start (default)
    await tester.pumpAndSettle();
    await typePin(tester, '123456');
    await tapText(tester, 'ဆိုင်ဖွင့်မယ်');
    await settle(tester, animating: true);

    expect(api.calls.where((x) => x.startsWith('google:register')).single,
        startsWith('google:register:ရွှေဝါ:grocery:+959790917041:123456'));
    expect(google.signIns, 1, reason: 'the account picked on Login is reused');
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(find.textContaining('OTP'), findsNothing);
  });

  testWidgets('register straight from Login: step 1 opens Google, then the shop steps', (tester) async {
    await boot(tester);
    await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('Google အကောင့်နဲ့ ဆိုင်ဖွင့်မယ်'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing, reason: 'no phone / SMS code on step 1');

    await tapText(tester, 'Google နဲ့ စမယ်');
    await settle(tester);
    expect(google.signIns, 1);
    expect(find.text('ဘယ်လိုဆိုင်လဲ?'), findsOneWidget, reason: 'step 2');
  });

  testWidgets('no shop on the Google account: open a new one or try another account; no phone + PIN sign-in', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
    await settle(tester);

    expect(find.byType(GoogleShopScreen), findsOneWidget);
    expect(find.text('ဒီ Google အကောင့်မှာ ဆိုင် မရှိသေးပါ'), findsOneWidget);
    expect(find.text('ဆိုင်အသစ် ဖွင့်မယ်'), findsOneWidget);
    expect(find.text('တခြားအကောင့်'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing, reason: 'no phone or PIN field to sign in with');
    expect(find.text('ဖုန်းနံပါတ်'), findsNothing);
    expect(api.calls, ['google:shops']);
  });

  testWidgets('locked out → "PIN မေ့နေပါသလား?" → Google → this phone\'s shop is chosen → new PIN twice → the app opens',
      (tester) async {
    final hash = await const PinHasher(iterations: 10, useIsolate: false).hash('123456');
    final session = testSession(api.tenantId, pinHash: hash);
    store.values.addAll({
      SecureKeys.tenantId: session.tenantId,
      SecureKeys.refreshToken: 'r',
      SecureKeys.pinHash: hash,
      SecureKeys.phone: '',
      SecureKeys.pinLockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
    });
    await tester.runAsync(() async {
      await LocalData(db).adopt(
          tenantId: api.tenantId, phone: '', shopName: 'ရွှေဝါ', templateId: 'grocery', deviceId: 'd', deviceCode: 'A',
          deviceLastSeq: 0);
      await db.writeState(SyncStateKeys.initialSyncDone, 'true');
    });
    // Two shops on the account: the one this phone holds is picked without asking.
    api.googleShopList = [
      const GoogleShop(tenantId: 'other', name: 'တခြားဆိုင်', templateId: 'grocery'),
      GoogleShop(tenantId: api.tenantId, name: 'ရွှေဝါ', templateId: 'grocery'),
    ];
    final c = await boot(tester, state: BootState(deviceId: newId(), session: session, initialSyncDone: true));
    expect(find.byType(UnlockScreen), findsOneWidget);

    await tester.tap(find.text('PIN မေ့နေပါသလား?'));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleShopScreen), findsOneWidget);

    await tapText(tester, 'Google နဲ့ အတည်ပြုမယ်');
    await settle(tester);
    expect(find.text('PIN အသစ် (၆ လုံး)'), findsOneWidget);
    await typePin(tester, '246810');
    await tapText(tester, 'ဆက်သွားမယ်');
    await tester.pumpAndSettle();
    expect(find.text('PIN အသစ် ထပ်ရိုက်ပါ'), findsOneWidget);
    await typePin(tester, '246810');
    await tapText(tester, 'PIN အသစ် သိမ်းမယ်');
    await settle(tester);

    expect(api.calls, ['google:shops', 'google:reset:${api.tenantId}:246810', 'google:signIn:${api.tenantId}:246810']);
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(find.byType(GoogleShopScreen), findsNothing);
  });

  testWidgets('reset: two different new PINs are refused before any call', (tester) async {
    api.googleShopList = const [GoogleShop(tenantId: 'shop-1', name: 'ရွှေဝါ', templateId: 'grocery')];
    final c = await boot(tester);
    c.read(appRouterProvider).push(Routes.pinReset);
    await tester.pumpAndSettle();
    await tapText(tester, 'Google နဲ့ အတည်ပြုမယ်');
    await settle(tester);
    await typePin(tester, '111111');
    await tapText(tester, 'ဆက်သွားမယ်');
    await tester.pumpAndSettle();
    await typePin(tester, '222222');
    await tapText(tester, 'PIN အသစ် သိမ်းမယ်');
    await tester.pumpAndSettle();

    expect(find.text('PIN အသစ် နှစ်ခါ မတူပါ။'), findsOneWidget);
    expect(api.calls, ['google:shops']);
  });

  testWidgets('the new screens fit 320 px wide with no overflow', (tester) async {
    api.googleShopList = const [
      GoogleShop(tenantId: 'a', name: 'ရွှေဝါ ကုန်စုံ အရောင်းဆိုင် (အမှတ် ၁၂၃)', templateId: 'grocery'),
      GoogleShop(tenantId: 'b', name: 'မြဆေးဆိုင်', templateId: 'pharmacy'),
    ];
    await boot(tester, size: const Size(320, 568));
    await tester.tap(find.text('Google နဲ့ ဝင်မယ်'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('ရွှေဝါ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
