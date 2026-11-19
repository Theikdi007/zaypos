import '../../../core/api/api_error.dart';

/// A user-facing failure: [message] is Burmese, [code] is stable.
class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message, {this.retryAfter});
  final String code;
  final String message;
  final Duration? retryAfter;

  factory AuthFailure.fromApi(ApiError e) => AuthFailure(e.code, e.message, retryAfter: e.retryAfter);

  @override
  String toString() => 'AuthFailure($code)';
}
