import 'dart:async';

import 'package:dio/dio.dart';

import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/session_store.dart';
import 'api_error.dart';

/// Refresh this long before the access token expires (§6).
const refreshAhead = Duration(seconds: 60);

/// Keeps the access token fresh. [refresh] is single-flight: callers that
/// arrive while a refresh is running share its result, so N parallel 401s
/// cause ONE `/auth/refresh`.
class TokenRefresher {
  TokenRefresher({
    required this.api,
    required this.store,
    required this.onSessionEnded,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  final AuthApi api;
  final SessionStore store;

  /// Refresh was refused (401/403, e.g. `device_revoked`): the session is
  /// over. Called with the server code. The local database (and outbox) stay.
  final Future<void> Function(String code) onSessionEnded;
  final DateTime Function() clock;

  Future<String?>? _inFlight;

  /// New access token, or null if the session ended. Network errors throw
  /// [ApiError] (the session is kept; try again later).
  Future<String?> refresh() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<String?> _run() async {
    final t = await store.tokens();
    if (t == null) return null;
    try {
      final r = await api.refresh(t.refresh);
      await store.saveTokens(r);
      return r.accessToken;
    } on ApiError catch (e) {
      if (e.status == 401 || e.status == 403) {
        await onSessionEnded(e.code);
        return null;
      }
      rethrow;
    }
  }

  /// The current access token, refreshed first if it expires within [refreshAhead].
  Future<String?> validAccessToken() async {
    final t = await store.tokens();
    if (t == null) return null;
    if (t.accessExpiresAt.isAfter(clock().add(refreshAhead))) return t.access;
    return refresh();
  }
}

/// Adds `Authorization: Bearer …`; on 401 refreshes once (single-flight) and
/// retries the request once.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.refresher, this.dio);
  final TokenRefresher refresher;

  /// The dio this interceptor is installed on (used for the retry).
  final Dio dio;

  static const _retried = 'authRetried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[_retried] == true) return handler.next(options);
    try {
      final token = await refresher.validAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiError catch (e) {
      handler.reject(DioException(requestOptions: options, error: e, type: DioExceptionType.connectionError));
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    if (err.response?.statusCode != 401 || opts.extra[_retried] == true) return handler.next(err);
    try {
      // Another request may already have refreshed: then just retry with the new token.
      final used = opts.headers['Authorization'];
      final current = (await refresher.store.tokens())?.access;
      final token = current != null && used != 'Bearer $current' ? current : await refresher.refresh();
      if (token == null) return handler.next(err);
      opts.headers['Authorization'] = 'Bearer $token';
      opts.extra[_retried] = true;
      handler.resolve(await dio.fetch<dynamic>(opts));
    } on DioException catch (e) {
      handler.next(e);
    } on ApiError {
      handler.next(err);
    }
  }
}

/// Dio for authenticated `/api/v1` calls (sync, me, devices, …).
Dio authedDio(String baseUrl, TokenRefresher refresher, {HttpClientAdapter? adapter}) {
  final dio = plainDio(baseUrl);
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.add(AuthInterceptor(refresher, dio));
  return dio;
}
