import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `--dart-define=API_BASE_URL=http://10.0.2.2:5076` (docs/mobile/phase3-sync.md §8).
/// Release builds must use an `https://` URL (BUG-55, see [checkApiBaseUrl]).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5076');

final apiBaseUrlProvider = Provider<String>((_) => apiBaseUrl);

/// True in release builds. A provider so tests can pretend to be a release build.
final isReleaseBuildProvider = Provider<bool>((_) => kReleaseMode);

/// Wall clock (UTC). Overridden in tests (token expiry, PIN lockout).
final clockProvider = Provider<DateTime Function()>((_) => () => DateTime.now().toUtc());

/// A release build was given a non-https API URL.
class InsecureApiUrl implements Exception {
  const InsecureApiUrl(this.url);
  final String url;

  @override
  String toString() =>
      'InsecureApiUrl: release builds only talk to an https:// API, but API_BASE_URL is "$url". '
      'Rebuild with --dart-define=API_BASE_URL=https://<your API host>.';
}

/// BUG-55: `dart:io` sockets ignore Android's cleartext policy and iOS ATS, so
/// the app enforces "release = HTTPS only" itself. Throws [InsecureApiUrl] for
/// a release build whose [url] is not `https://` with a host. Debug and
/// profile builds may use `http://` (emulator, simulator, LAN).
void checkApiBaseUrl(String url, {bool release = kReleaseMode}) {
  if (!release) return;
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme.toLowerCase() != 'https' || u.host.isEmpty) throw InsecureApiUrl(url);
}

/// The guard on every dio (BUG-55): in a release build any request whose
/// final URL is not `https://` is refused before a socket is opened, so no
/// PIN, token or sale can leave the phone in clear text, whatever the base
/// URL or an absolute path says.
class HttpsOnlyInterceptor extends Interceptor {
  HttpsOnlyInterceptor({this.release = kReleaseMode});
  final bool release;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (release && options.uri.scheme.toLowerCase() != 'https') {
      return handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: InsecureApiUrl(options.uri.toString()),
        message: 'Refused: release builds only send https:// requests.',
      ));
    }
    handler.next(options);
  }
}
