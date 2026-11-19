// Google Sign-In (docs/backend/auth-google.md §5): error mapping and the AuthController flows.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';

void main() {
  group('Google errors → Burmese', () {
    AuthFailure map(GoogleSignInExceptionCode code, [String? d, bool android = true]) =>
        googleFailure(code, d, android: android);

    test('cancelled / no account / Play services / offline / other each have their own Burmese message', () {
      expect(map(GoogleSignInExceptionCode.canceled).code, 'google_cancelled');
      expect(map(GoogleSignInExceptionCode.unknownError, 'No credential available: none').code, 'google_no_account');
      expect(map(GoogleSignInExceptionCode.providerConfigurationError, 'Credential Manager not supported.').code,
          'google_play_services');
      expect(map(GoogleSignInExceptionCode.unknownError, 'A network error (timeout) occurred').code, 'network');
      expect(map(GoogleSignInExceptionCode.interrupted, 'The Internet connection appears to be offline.').code, 'network');
      expect(map(GoogleSignInExceptionCode.clientConfigurationError, 'serverClientId must be provided').code,
          'google_not_configured');
      expect(map(GoogleSignInExceptionCode.uiUnavailable).code, 'google_failed');
      expect(map(GoogleSignInExceptionCode.providerConfigurationError, null, false).code, 'google_failed',
          reason: 'iOS has no Play services');

      final messages = {
        for (final f in [
          map(GoogleSignInExceptionCode.canceled),
          map(GoogleSignInExceptionCode.unknownError, 'No credential available'),
          map(GoogleSignInExceptionCode.providerConfigurationError),
          map(GoogleSignInExceptionCode.unknownError, 'network'),
          map(GoogleSignInExceptionCode.uiUnavailable),
        ])
          f.message,
      };
      expect(messages, hasLength(5));
      for (final m in messages) {
        expect(RegExp(r'[က-႟]').hasMatch(m), isTrue, reason: m);
      }
    });

    test('every new server code has its own Burmese message (not the generic one)', () {
      final generic = apiErrorMessage('something_unknown');
      for (final code in [
        'google_token_invalid',
        'google_unavailable',
        'shop_not_found',
        'google_shop_limit',
        'otp_disabled',
      ]) {
        expect(apiErrorMessage(code), isNot(generic), reason: code);
      }
    });

    test('a build without client ids says "not configured" instead of crashing', () async {
      final g = PluginGoogleAuth(serverClientId: '', iosClientId: '');
      expect(() => g.signIn(), throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'google_not_configured')));
    });

    test('the OTP flow is off unless AUTH_OTP_ENABLED is set', () {
      expect(authOtpEnabled, isFalse);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(otpEnabledProvider), isFalse);
    });
  });

  group('AuthController with Google', () {
    late AppDatabase db;
    late MemorySecureStore store;
    late FakeAuthApi api;
    late FakeGoogleAuth google;
    final containers = <ProviderContainer>[];

    setUp(() {
      db = memoryDb();
      store = MemorySecureStore();
      api = FakeAuthApi();
      google = FakeGoogleAuth();
    });
    tearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      containers.clear();
      await db.close();
    });

    Future<ProviderContainer> launch() async {
      final boot = await bootstrap(db, store);
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, boot, store),
        authApiProvider.overrideWithValue(api),
        googleAuthProvider.overrideWithValue(google),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 19, 9)),
      ]);
      containers.add(c);
      return c;
    }

    AuthController auth(ProviderContainer c) => c.read(authControllerProvider.notifier);

    Future<void> addCustomerUnit(ProviderContainer c) async {
      final t = nowUtc();
      await c.read(customerServiceProvider).create(
            Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'x', phone: '', createdAt: t, updatedAt: t),
          );
    }

    test('"who is this user": the picker, then the shops of that account; the ID token is kept only in memory', () async {
      api.googleShopList = const [GoogleShop(tenantId: 't-1', name: 'ရွှေဝါ', templateId: 'grocery')];
      final c = await launch();

      final flow = await auth(c).googleSignIn();

      expect(flow.shops.single.tenantId, 't-1');
      expect(flow.email, 'owner@gmail.com');
      expect(api.idTokens, ['google-id-token-1']);
      expect(store.values.values.any((v) => v.contains('google-id-token')), isFalse);
    });

    test('cancel on the picker: a Burmese failure, no API call, nothing stored', () async {
      google.nextError = const AuthFailure('google_cancelled', GoogleMessages.cancelled);
      final c = await launch();

      await expectLater(auth(c).googleSignIn(), throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'google_cancelled')));
      expect(api.calls, isEmpty);
      expect(c.read(googleFlowProvider), isNull);
    });

    test('new phone: choose the shop + PIN → session stored, unlocked, the token dropped', () async {
      api.googleShopList = [GoogleShop(tenantId: api.tenantId, name: 'ရွှေဝါ', templateId: 'pharmacy')];
      final c = await launch();
      await auth(c).googleSignIn();

      await auth(c).signInToShop(api.tenantId, '123456');

      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(api.calls.last, 'google:signIn:${api.tenantId}:123456');
      expect(api.idTokens.last, 'google-id-token-1');
      final s = c.read(sessionProvider);
      expect((s.tenantId, s.shopName, s.phone), (api.tenantId, 'ရွှေဝါ', ''));
      expect(store.values[SecureKeys.pinHash], startsWith('pbkdf2-sha256\$'), reason: 'the offline PIN works as before');
      expect(c.read(googleFlowProvider), isNull);
    });

    test('the same shop again with unsent units: allowed and kept (the guard compares the tenant id)', () async {
      api.googleShopList = [GoogleShop(tenantId: api.tenantId, name: 'ရွှေဝါ', templateId: 'pharmacy')];
      final c = await launch();
      await auth(c).googleSignIn();
      await auth(c).signInToShop(api.tenantId, '123456');
      await addCustomerUnit(c);
      await auth(c).signOut();

      await auth(c).googleSignIn();
      await auth(c).signInToShop(api.tenantId, '123456');

      expect(await LocalData(db).pendingUnits(), 1);
      expect(google.signOuts, 1, reason: 'sign-out forgets the Google account (picker next time)');
    });

    test('another shop while the outbox has units: refused BEFORE the sign-in call', () async {
      api.googleShopList = [GoogleShop(tenantId: api.tenantId, name: 'ရွှေဝါ', templateId: 'pharmacy')];
      final c = await launch();
      await auth(c).googleSignIn();
      await auth(c).signInToShop(api.tenantId, '123456');
      await addCustomerUnit(c);
      await auth(c).signOut();
      api.calls.clear();

      await auth(c).googleSignIn();
      await expectLater(auth(c).signInToShop('other-tenant', '123456'),
          throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'outbox_not_empty')));
      expect(api.calls, ['google:shops']);
    });

    test('register: Google → shop + owner phone (normalized) + PIN; device A comes from the server', () async {
      final c = await launch();
      await auth(c).googleSignIn();
      api.deviceCode = 'A';

      await auth(c).registerWithGoogle(shopName: 'ရွှေဝါ', rawOwnerPhone: '09 790 917 041', templateId: 'grocery', pin: '123456');

      expect(api.calls.last, 'google:register:ရွှေဝါ:grocery:+959790917041:123456');
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect((await db.select(db.devices).getSingle()).code, 'A');
    });

    test('register refuses a bad owner phone, a short PIN or a missing Google step without calling the API', () async {
      final c = await launch();
      await expectLater(
          auth(c).registerWithGoogle(shopName: 'x', rawOwnerPhone: '09 790', templateId: 'grocery', pin: '123456'),
          throwsA(isA<AuthFailure>().having((f) => f.message, 'message', AuthMessages.badOwnerPhone)));
      await expectLater(
          auth(c).registerWithGoogle(shopName: 'x', rawOwnerPhone: '0979091704', templateId: 'grocery', pin: '123'),
          throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'validation')));
      await expectLater(
          auth(c).registerWithGoogle(shopName: 'x', rawOwnerPhone: '0979091704', templateId: 'grocery', pin: '123456'),
          throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'google_again')));
      expect(api.calls, isEmpty);
    });

    test('forgot PIN: Google → reset → signs in with the NEW PIN; the local lockout is cleared', () async {
      api.googleShopList = [GoogleShop(tenantId: api.tenantId, name: 'ရွှေဝါ', templateId: 'pharmacy')];
      final c = await launch();
      await auth(c).googleSignIn();
      await auth(c).signInToShop(api.tenantId, '123456');
      await store.write(SecureKeys.pinFailures, '0');
      await store.write(SecureKeys.pinLockedUntil, DateTime.utc(2026, 11, 19, 9, 10).toIso8601String());

      await auth(c).googleSignIn();
      await auth(c).resetPinWithGoogle(tenantId: api.tenantId, newPin: '654321');

      expect(api.calls.sublist(api.calls.length - 2),
          ['google:reset:${api.tenantId}:654321', 'google:signIn:${api.tenantId}:654321']);
      expect(await auth(c).lockRemaining(), isNull);
    });

    test('an expired Google token from the server drops the flow so the screen asks for Google again', () async {
      final c = await launch();
      await auth(c).googleSignIn();
      api.nextError = const ApiError(401, 'google_token_invalid');

      await expectLater(auth(c).signInToShop('t', '123456'),
          throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'google_token_invalid')));
      expect(c.read(googleFlowProvider), isNull);
    });
  });
}
