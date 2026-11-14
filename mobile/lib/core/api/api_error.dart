import 'package:dio/dio.dart';

/// A failed API call: a server ProblemDetails (stable [code]) or a network
/// failure ([isNetwork], code `network`).
class ApiError implements Exception {
  const ApiError(this.status, this.code, {this.detail, this.retryAfter});

  const ApiError.network([this.detail])
      : status = 0,
        code = 'network',
        retryAfter = null;

  /// HTTP status; 0 = no response.
  final int status;
  final String code;
  final String? detail;
  final Duration? retryAfter;

  bool get isNetwork => status == 0;

  /// Burmese message for the user.
  String get message => apiErrorMessage(code, retryAfter: retryAfter);

  factory ApiError.fromDio(DioException e) {
    final r = e.response;
    if (r == null) return ApiError.network(e.message);
    final data = r.data;
    final retry = int.tryParse(r.headers.value('retry-after') ?? '');
    final status = r.statusCode ?? 0;
    final code = data is Map ? (data['code'] ?? data['title'])?.toString() : null;
    return ApiError(
      status,
      code ?? (status >= 500 ? 'server' : status == 403 ? 'forbidden' : 'unknown'),
      detail: data is Map ? data['detail']?.toString() : null,
      retryAfter: retry == null ? null : Duration(seconds: retry),
    );
  }

  @override
  String toString() => 'ApiError($status, $code${detail == null ? '' : ': $detail'})';
}

/// 15 → "၁၅".
String mmNumber(int n) => n.toString().split('').map((c) => '၀၁၂၃၄၅၆၇၈၉'[int.parse(c)]).join();

/// Whole minutes, rounded up, at least 1.
int minutesUp(Duration d) {
  final m = (d.inSeconds / 60).ceil();
  return m < 1 ? 1 : m;
}

/// Server ProblemDetails codes (docs/backend/README.md §4) → Burmese.
String apiErrorMessage(String code, {Duration? retryAfter}) => switch (code) {
      'otp_invalid' => 'ကုဒ် မှားနေပါတယ် (သို့) သက်တမ်းကုန်သွားပါပြီ။',
      'otp_rate_limited' => 'ကုဒ်တောင်းတာ များသွားပါပြီ။ နောက်မှ ပြန်ကြိုးစားပါ။',
      'phone_registered' => 'ဒီဖုန်းနံပါတ်နဲ့ ဆိုင်ရှိပြီးသားပါ။ "ဝင်မယ်" ကနေ ဝင်ပါ။',
      'invalid_credentials' => 'ဖုန်းနံပါတ် (သို့) PIN မှားနေပါတယ်။',
      'pin_locked' => retryAfter == null
          ? 'PIN မှားတာ များသွားလို့ ခဏပိတ်ထားပါတယ်။'
          : 'PIN မှားတာ များသွားလို့ ခဏပိတ်ထားပါတယ်။ ${mmNumber(minutesUp(retryAfter))} မိနစ်နေမှ ပြန်ကြိုးစားပါ။',
      'device_revoked' => 'ဆိုင်ပိုင်ရှင်က ဒီဖုန်းကို ဖယ်ရှားထားပါတယ်။ App ကို ပြန်ထည့်ပြီးမှ ဝင်ပါ။',
      'device_conflict' => 'ဒီဖုန်းကို တခြားဆိုင်မှာ စာရင်းသွင်းထားပါတယ်။',
      'rate_limited' => 'ကြိုးစားတာ များသွားပါပြီ။ ခဏနေမှ ပြန်ကြိုးစားပါ။',
      'validation' => 'ထည့်ထားတာ တစ်ခုခု မှားနေပါတယ်။ ပြန်စစ်ပေးပါ။',
      'invalid_refresh_token' || 'invalid_token' => 'အချိန်ကြာသွားလို့ ပြန်ဝင်ပေးပါ။',
      'cannot_revoke_current_device' => 'ဒီဖုန်းကို ဒီဖုန်းကနေ ဖယ်လို့မရပါ။ တခြားဖုန်းကနေ ဖယ်ပါ (သို့) ထွက်ပါ။',
      'not_found' => 'မတွေ့ပါ။ ဖယ်ပြီးသား ဖြစ်နိုင်ပါတယ်။',
      'forbidden' => 'ဆိုင်ပိုင်ရှင်ပဲ လုပ်လို့ရပါတယ်။',
      'network' => 'အင်တာနက် မရပါ။ လိုင်းရမှ ပြန်ကြိုးစားပါ။',
      'server' => 'Server မှာ ပြဿနာ ဖြစ်နေပါတယ်။ ခဏနေမှ ပြန်ကြိုးစားပါ။',
      _ => 'တစ်ခုခု မှားသွားပါတယ်။ ပြန်ကြိုးစားပါ။',
    };
