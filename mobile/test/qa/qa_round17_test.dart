// QA round 17: the uncommitted api_error.dart change (2026-11-17): a 5xx WITHOUT our own `code` maps to 'server' and its
// Burmese message, even when ASP.NET sends its default ProblemDetails title (what the user saw today when a missing migration
// made GET /api/v1/sync/pull return 500). Our own codes and 4xx titles keep working as before.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';

DioException _res(int status, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/sync/pull'),
      response: Response(requestOptions: RequestOptions(path: '/api/v1/sync/pull'), statusCode: status, data: body),
    );

void main() {
  const serverMsg = 'ဆာဗာမှာ ပြဿနာ ဖြစ်နေပါတယ်။ ခဏနေမှ ပြန်ကြိုးစားပါ။';

  test('TC-SYNC-NEW-31 a 500 with ASP.NET\'s default ProblemDetails (title only) shows the server message, not the title', () {
    final e = ApiError.fromDio(_res(500, {
      'type': 'https://tools.ietf.org/html/rfc9110#section-15.6.1',
      'title': 'An error occurred while processing your request.',
      'status': 500,
      'traceId': '00-abc-def-00',
    }));
    expect(e.code, 'server');
    expect(e.message, serverMsg);
  });

  test('TC-SYNC-NEW-31 other 5xx: no body, text body, 503 with a title → server', () {
    expect(ApiError.fromDio(_res(500, null)).code, 'server');
    expect(ApiError.fromDio(_res(500, 'Internal Server Error')).code, 'server');
    expect(ApiError.fromDio(_res(503, {'title': 'Service Unavailable'})).message, serverMsg);
  });

  test('TC-SYNC-NEW-31 our own code on a 5xx and 4xx titles are unchanged', () {
    expect(ApiError.fromDio(_res(500, {'code': 'pin_locked', 'title': 'x'})).code, 'pin_locked');
    expect(ApiError.fromDio(_res(400, {'title': 'otp_invalid'})).code, 'otp_invalid');
    expect(ApiError.fromDio(_res(403, {})).code, 'forbidden');
    expect(ApiError.fromDio(_res(404, {})).code, 'unknown');
  });
}
