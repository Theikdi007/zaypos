import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_client.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/features/auth/data/session_store.dart';

import 'fake_auth_api.dart';

/// A protected endpoint: 200 for the currently valid token, 401 otherwise.
class _ServerAdapter implements HttpClientAdapter {
  _ServerAdapter(this.validToken);
  final String Function() validToken;
  final seenAuth = <String?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final auth = options.headers['Authorization'] as String?;
    seenAuth.add(auth);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final ok = auth == 'Bearer ${validToken()}';
    return ResponseBody.fromString(
      jsonEncode(ok ? {'ok': true} : {'title': 'invalid_token', 'code': 'invalid_token', 'status': 401}),
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeAuthApi api;
  late SessionStore store;
  late List<String> ended;
  late DateTime now;
  var valid = 'access-new';

  Future<void> seedTokens({required String access, required DateTime expires}) async {
    await store.store.write(SecureKeys.accessToken, access);
    await store.store.write(SecureKeys.accessExpiresAt, expires.toIso8601String());
    await store.store.write(SecureKeys.refreshToken, 'refresh-0');
  }

  setUp(() {
    api = FakeAuthApi();
    store = SessionStore(MemorySecureStore());
    ended = [];
    now = DateTime.utc(2026, 11, 12, 10);
  });

  TokenRefresher refresher() => TokenRefresher(
        api: api,
        store: store,
        onSessionEnded: (code) async => ended.add(code),
        clock: () => now,
      );

  test('3 parallel 401s cause ONE /auth/refresh, then every request is retried and succeeds', () async {
    await seedTokens(access: 'access-old', expires: now.add(const Duration(minutes: 10)));
    final r = refresher();
    // The server already considers the old token invalid; the refreshed one is valid.
    final adapter = _ServerAdapter(() => valid);
    valid = 'access-1'; // FakeAuthApi issues access-1 on the first refresh
    final dio = authedDio('http://test', r, adapter: adapter);

    final results = await Future.wait([for (var i = 0; i < 3; i++) dio.get<Map<String, dynamic>>('/api/v1/me')]);

    expect(results.map((x) => x.statusCode), [200, 200, 200]);
    expect(api.calls.where((c) => c.startsWith('refresh')), ['refresh:refresh-0']);
    expect((await store.tokens())!.access, 'access-1');
    expect(adapter.seenAuth.where((a) => a == 'Bearer access-old'), hasLength(3));
    expect(adapter.seenAuth.where((a) => a == 'Bearer access-1'), hasLength(3));
    expect(ended, isEmpty);
  });

  test('a token expiring within 60 s is refreshed before the request (once for parallel calls)', () async {
    await seedTokens(access: 'access-old', expires: now.add(const Duration(seconds: 59)));
    valid = 'access-1';
    final adapter = _ServerAdapter(() => valid);
    final dio = authedDio('http://test', refresher(), adapter: adapter);

    await Future.wait([dio.get<dynamic>('/a'), dio.get<dynamic>('/b')]);

    expect(api.calls, ['refresh:refresh-0']);
    expect(adapter.seenAuth, everyElement('Bearer access-1'), reason: 'no request went out with the old token');
  });

  test('a fresh token is used as is', () async {
    await seedTokens(access: 'access-ok', expires: now.add(const Duration(minutes: 5)));
    valid = 'access-ok';
    final dio = authedDio('http://test', refresher(), adapter: _ServerAdapter(() => valid));
    expect((await dio.get<dynamic>('/a')).statusCode, 200);
    expect(api.calls, isEmpty);
  });

  test('refresh refused with 403 device_revoked ends the session once and the request fails with 401', () async {
    await seedTokens(access: 'access-old', expires: now.add(const Duration(minutes: 10)));
    api.refreshError = const ApiError(403, 'device_revoked');
    valid = 'never';
    final dio = authedDio('http://test', refresher(), adapter: _ServerAdapter(() => valid));

    final errors = await Future.wait([
      for (var i = 0; i < 3; i++)
        dio.get<dynamic>('/a').then<Object?>((_) => null, onError: (Object e) => e),
    ]);

    expect(errors, everyElement(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)));
    expect(api.calls.where((c) => c.startsWith('refresh')), hasLength(1));
    expect(ended, ['device_revoked']);
  });

  test('a network failure during refresh keeps the session', () async {
    await seedTokens(access: 'access-old', expires: now.add(const Duration(minutes: 10)));
    api.refreshError = const ApiError.network();
    final dio = authedDio('http://test', refresher(), adapter: _ServerAdapter(() => 'never'));
    await expectLater(dio.get<dynamic>('/a'), throwsA(isA<DioException>()));
    expect(ended, isEmpty);
    expect((await store.tokens())!.refresh, 'refresh-0');
  });

  group('ApiError', () {
    DioException problem(int status, Map<String, Object?> body, {String? retryAfter}) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: body,
            headers: Headers.fromMap({
              if (retryAfter != null) 'retry-after': [retryAfter],
            }),
          ),
        );

    test('reads the ProblemDetails code, detail and Retry-After', () {
      final e = ApiError.fromDio(problem(423, {'code': 'pin_locked', 'detail': 'Too many'}, retryAfter: '900'));
      expect((e.status, e.code, e.detail, e.retryAfter), (423, 'pin_locked', 'Too many', const Duration(minutes: 15)));
      expect(e.message, contains('၁၅ မိနစ်'));
    });

    test('no response = network; 5xx without code = server', () {
      expect(ApiError.fromDio(DioException(requestOptions: RequestOptions(path: '/x'))).isNetwork, isTrue);
      expect(ApiError.fromDio(problem(502, {})).code, 'server');
    });

    test('every server auth code has its own Burmese message', () {
      const codes = [
        'otp_invalid', 'otp_rate_limited', 'phone_registered', 'invalid_credentials', 'pin_locked',
        'device_revoked', 'device_conflict', 'rate_limited', 'validation', 'invalid_refresh_token', 'network',
      ];
      final fallback = apiErrorMessage('something_new');
      for (final c in codes) {
        expect(apiErrorMessage(c), isNot(fallback), reason: c);
      }
      expect(codes.map(apiErrorMessage).toSet(), hasLength(codes.length));
    });
  });
}
