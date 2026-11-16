// BUG-55: release builds talk to the API over https only. dart:io ignores
// Android's cleartext policy and iOS ATS, so the app enforces it itself:
// (1) a release build with a non-https API_BASE_URL refuses to start, and
// (2) every dio refuses a non-https request in release, before any socket.
// `flutter test` runs in debug, so "release" is passed in explicitly here; the
// real release APK is checked by tool/release_https_check.sh (QA, emulator).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_client.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/main.dart';

/// Counts requests that reached the "network" and answers 200 {}.
class _CountingAdapter implements HttpClientAdapter {
  final hits = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    hits.add(o.uri);
    return ResponseBody.fromString(jsonEncode({}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('checkApiBaseUrl', () {
    test('release: only https with a host is accepted', () {
      for (final bad in ['http://10.0.2.2:5076', 'http://localhost:5076', 'HTTP://api.zaypos.app', 'https://', 'api.zaypos.app', 'ws://x', '']) {
        expect(() => checkApiBaseUrl(bad, release: true), throwsA(isA<InsecureApiUrl>()), reason: bad);
      }
      for (final good in ['https://api.zaypos.app', 'HTTPS://api.zaypos.app:8443', ' https://api.zaypos.app/ ']) {
        expect(() => checkApiBaseUrl(good, release: true), returnsNormally, reason: good);
      }
    });

    test('debug / profile may use http (emulator, simulator, LAN)', () {
      expect(() => checkApiBaseUrl('http://10.0.2.2:5076', release: false), returnsNormally);
    });

    test('the build default (no --dart-define) is http, so a release build without an https URL cannot start', () {
      expect(apiBaseUrl.startsWith('https://'), isFalse, reason: 'the test run has no API_BASE_URL define');
      expect(() => checkApiBaseUrl(apiBaseUrl, release: true), throwsA(isA<InsecureApiUrl>()));
    });
  });

  group('startup', () {
    testWidgets('release + http URL: the refusal screen is shown instead of the app, with the URL', (tester) async {
      final screen = insecureBuildScreen('http://10.0.2.2:5076', release: true);
      expect(screen, isNotNull);
      await tester.pumpWidget(screen!);
      await tester.pumpAndSettle();
      expect(find.text('ZayPOS ကို ဖွင့်လို့ မရပါ'), findsOneWidget);
      expect(find.textContaining('http://10.0.2.2:5076'), findsOneWidget);
      expect(find.textContaining('must be https://'), findsOneWidget);
    });

    test('release + https URL, and any debug build: the app starts normally', () {
      expect(insecureBuildScreen('https://api.zaypos.app', release: true), isNull);
      expect(insecureBuildScreen('http://10.0.2.2:5076', release: false), isNull);
    });
  });

  group('dio guard (every client)', () {
    test('release: a plain-HTTP request is refused and never reaches the network', () async {
      final adapter = _CountingAdapter();
      final dio = plainDio('http://10.0.2.2:5076', release: true)..httpClientAdapter = adapter;
      final e = await dio.post<dynamic>('/api/v1/auth/login', data: {'pin': '111111'}).then<Object?>((_) => null,
          onError: (Object e) => e);
      expect(e, isA<DioException>());
      expect((e! as DioException).error, isA<InsecureApiUrl>());
      expect(adapter.hits, isEmpty, reason: 'no byte of the PIN may leave the phone');
    });

    test('release: an absolute http:// path is refused even with an https base URL', () async {
      final adapter = _CountingAdapter();
      final dio = plainDio('https://api.zaypos.app', release: true)..httpClientAdapter = adapter;
      await expectLater(dio.get<dynamic>('http://api.zaypos.app/api/v1/sync/limits'), throwsA(isA<DioException>()));
      expect(adapter.hits, isEmpty);
    });

    test('release: https requests go through', () async {
      final adapter = _CountingAdapter();
      final dio = plainDio('https://api.zaypos.app', release: true)..httpClientAdapter = adapter;
      await dio.get<dynamic>('/api/v1/sync/limits');
      expect(adapter.hits.single.toString(), 'https://api.zaypos.app/api/v1/sync/limits');
    });

    test('debug: http still works (developer setup)', () async {
      final adapter = _CountingAdapter();
      final dio = plainDio('http://10.0.2.2:5076', release: false)..httpClientAdapter = adapter;
      await dio.get<dynamic>('/api/v1/sync/limits');
      expect(adapter.hits, hasLength(1));
    });

    test('release: the authenticated dio (sync, devices) refuses http too, before asking for a token', () async {
      final adapter = _CountingAdapter();
      final refresher = _NoTokenRefresher();
      final dio = authedDio('http://10.0.2.2:5076', refresher, adapter: adapter, release: true);
      await expectLater(dio.post<dynamic>('/api/v1/sync/push', data: {}), throwsA(isA<DioException>()));
      expect(adapter.hits, isEmpty);
      expect(refresher.asked, 0, reason: 'the guard runs first, so no token is read or refreshed for an http URL');
    });
  });
}

class _NoTokenRefresher implements TokenRefresher {
  var asked = 0;
  @override
  Future<String?> validAccessToken() async {
    asked++;
    return 'token';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

