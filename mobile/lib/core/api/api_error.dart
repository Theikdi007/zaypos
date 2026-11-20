import 'package:dio/dio.dart';

/// A failed API call: a server ProblemDetails (stable [code]) or a network
/// failure ([isNetwork], code `network`).
class ApiError implements Exception {
  const ApiError(this.status, this.code, {this.detail, this.retryAfter, this.attemptsLeft});

  const ApiError.network([this.detail])
      : status = 0,
        code = 'network',
        retryAfter = null,
        attemptsLeft = null;

  /// HTTP status; 0 = no response.
  final int status;
  final String code;
  final String? detail;
  final Duration? retryAfter;

  /// `invalid_credentials`: wrong PINs still allowed before the 15-minute lock.
  final int? attemptsLeft;

  bool get isNetwork => status == 0;

  /// Burmese message for the user.
  String get message => apiErrorMessage(code, retryAfter: retryAfter, attemptsLeft: attemptsLeft);

  factory ApiError.fromDio(DioException e) {
    final r = e.response;
    if (r == null) return ApiError.network(e.message);
    final data = r.data;
    final retry = int.tryParse(r.headers.value('retry-after') ?? '');
    final status = r.statusCode ?? 0;
    // A 5xx without our own `code` is a server fault: never use its ProblemDetails
    // title ("An error occurred while processing your request.") as the code.
    final code = data is Map ? (data['code'] ?? (status >= 500 ? null : data['title']))?.toString() : null;
    return ApiError(
      status,
      code ?? (status >= 500 ? 'server' : status == 403 ? 'forbidden' : 'unknown'),
      detail: data is Map ? data['detail']?.toString() : null,
      retryAfter: retry == null ? null : Duration(seconds: retry),
      attemptsLeft: data is Map ? (data['attemptsLeft'] as num?)?.toInt() : null,
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

/// A wrong PIN, on the server (Google + PIN) and offline (unlock). Only the PIN is checked:
/// there is no phone number in either, so the message names the PIN alone.
String wrongPinMessage(int? attemptsLeft) => attemptsLeft == null || attemptsLeft < 1
    ? 'PIN မှားနေပါတယ်။'
    : 'PIN မှားနေပါတယ်။ နောက်ထပ် ${mmNumber(attemptsLeft)} ကြိမ် ကြိုးစားလို့ရပါတယ်။';

/// Server ProblemDetails codes (docs/backend/README.md §4) → Burmese.
String apiErrorMessage(String code, {Duration? retryAfter, int? attemptsLeft}) => switch (code) {
      'otp_invalid' => 'ကုဒ် မှားနေပါတယ် (သို့) သက်တမ်းကုန်သွားပါပြီ။',
      'otp_rate_limited' => 'ကုဒ်တောင်းတာ များသွားပါပြီ။ နောက်မှ ပြန်ကြိုးစားပါ။',
      // 503 from POST /auth/otp when the SMS provider (SMSPoh) is down or refuses the message.
      'sms_unavailable' => 'SMS ပို့မရပါ။ ခဏနေ ထပ်ကြိုးစားပါ။',
      'phone_registered' => 'ဒီဖုန်းနံပါတ်နဲ့ ဆိုင်ရှိပြီးသားပါ။ "ဝင်မယ်" ကနေ ဝင်ပါ။',
      // Google sign-in (docs/backend/auth-google.md §3).
      'google_token_invalid' => 'Google အကောင့်နဲ့ ပြန်ဝင်ပေးပါ။',
      'google_unavailable' => 'Google နဲ့ အခု စစ်လို့ မရပါ။ ခဏနေ ပြန်ကြိုးစားပါ။',
      'shop_not_found' => 'ဒီ Google အကောင့်မှာ ဒီဆိုင် မရှိပါ။ ဆိုင်ဖွင့်တုန်းက Google အကောင့်နဲ့ ဝင်ပါ။',
      'google_shop_limit' => 'Google အကောင့်တစ်ခုမှာ ဆိုင် ၁၀ ဆိုင်ထက် ပိုဖွင့်လို့ မရပါ။',
      'otp_disabled' => 'SMS ကုဒ်နဲ့ ဝင်တာ ပိတ်ထားပါတယ်။ Google အကောင့်နဲ့ ဝင်ပါ။',
      'invalid_credentials' => wrongPinMessage(attemptsLeft),
      'pin_locked' => retryAfter == null
          ? 'PIN မှားတာ များသွားလို့ ခဏပိတ်ထားပါတယ်။'
          : 'PIN မှားတာ များသွားလို့ ခဏပိတ်ထားပါတယ်။ ${mmNumber(minutesUp(retryAfter))} မိနစ်နေမှ ပြန်ကြိုးစားပါ။',
      'device_revoked' => 'ဆိုင်ပိုင်ရှင်က ဒီဖုန်းကို ဖယ်ရှားထားပါတယ်။ အက်ပ်ကို ပြန်ထည့်ပြီးမှ ဝင်ပါ။',
      'device_conflict' => 'ဒီဖုန်းကို တခြားဆိုင်မှာ စာရင်းသွင်းထားပါတယ်။',
      'rate_limited' => 'ကြိုးစားတာ များသွားပါပြီ။ ခဏနေမှ ပြန်ကြိုးစားပါ။',
      'validation' => 'ထည့်ထားတာ တစ်ခုခု မှားနေပါတယ်။ ပြန်စစ်ပေးပါ။',
      'invalid_refresh_token' || 'invalid_token' => 'အချိန်ကြာသွားလို့ ပြန်ဝင်ပေးပါ။',
      'cannot_revoke_current_device' => 'ဒီဖုန်းကို ဒီဖုန်းကနေ ဖယ်လို့မရပါ။ တခြားဖုန်းကနေ ဖယ်ပါ (သို့) ထွက်ပါ။',
      'not_found' => 'မတွေ့ပါ။ ဖယ်ပြီးသား ဖြစ်နိုင်ပါတယ်။',
      'forbidden' => 'ဆိုင်ပိုင်ရှင်ပဲ လုပ်လို့ရပါတယ်။',
      'network' => 'အင်တာနက် မရပါ။ လိုင်းရမှ ပြန်ကြိုးစားပါ။',
      'server' => 'ဆာဗာမှာ ပြဿနာ ဖြစ်နေပါတယ်။ ခဏနေမှ ပြန်ကြိုးစားပါ။',
      _ => 'တစ်ခုခု မှားသွားပါတယ်။ ပြန်ကြိုးစားပါ။',
    };
