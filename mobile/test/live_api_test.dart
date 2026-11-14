import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_client.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/session_store.dart';

/// Against a running backend (skipped otherwise):
///   ZAYPOS_LIVE_API=http://127.0.0.1:5076 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
///   flutter test test/live_api_test.dart
/// Request the OTP first (POST /auth/otp, purpose register); the dev backend prints the code.
void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('register → login → refresh → authed GET /me on the real backend', () async {
    final api = DioAuthApi(plainDio(base!));
    final deviceId = newId();

    final reg = await api.register(
      phone: phone!, otp: otp!, shopName: 'Live test', templateId: 'pharmacy', pin: '135790', deviceId: deviceId,
      deviceName: 'flutter-test',
    );
    expect(reg.deviceId, deviceId);
    expect(reg.deviceCode, 'A');
    expect(reg.templateId, 'pharmacy');
    expect(reg.role, 'owner');
    expect(reg.accessExpiresAt.isAfter(DateTime.now().toUtc()), isTrue);

    await expectLater(
      api.login(phone: phone, pin: '000000', deviceId: deviceId),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    final login = await api.login(phone: phone, pin: '135790', deviceId: deviceId);
    expect(login.tenantId, reg.tenantId);

    final store = SessionStore(MemorySecureStore());
    await store.save(login, phone: phone, pinHash: 'x');
    // Pretend the access token is about to expire: the interceptor refreshes first.
    await store.store.write(SecureKeys.accessExpiresAt, DateTime.now().toUtc().toIso8601String());
    final ended = <String>[];
    final refresher = TokenRefresher(api: api, store: store, onSessionEnded: (c) async => ended.add(c));
    final dio = authedDio(base, refresher);

    final results = await Future.wait([for (var i = 0; i < 3; i++) dio.get<Map<String, dynamic>>('/api/v1/me')]);
    for (final me in results) {
      expect(me.data!['tenant']['id'], reg.tenantId);
      expect(me.data!['currentDeviceId'], deviceId);
    }
    expect((await store.tokens())!.refresh, isNot(login.refreshToken), reason: 'rotated once');
    expect(ended, isEmpty);

    final otpAgain = api.requestOtp(phone, OtpPurpose.register);
    await expectLater(otpAgain, throwsA(isA<ApiError>().having((e) => e.code, 'code', 'phone_registered')));
  }, skip: skip);
}
