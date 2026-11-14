import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';

/// Records every call; answers like the backend for one shop.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({String? tenantId, this.deviceCode = 'B', this.deviceLastSeq = 7, this.shopName = 'ရွှေဝါ'})
      : tenantId = tenantId ?? newId();

  String tenantId;
  String deviceCode;
  int deviceLastSeq;
  String shopName;

  final calls = <String>[];
  final deviceIds = <String>[];

  /// Thrown by the next login/register (then cleared).
  ApiError? nextError;

  /// Thrown by refresh (every time) if set.
  ApiError? refreshError;
  Duration refreshDelay = const Duration(milliseconds: 5);
  int _token = 0;

  AuthResult result(String deviceId) => AuthResult(
        accessToken: 'access-${++_token}',
        accessExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
        refreshToken: 'refresh-$_token',
        refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 90)),
        userId: 'user-1',
        userName: shopName,
        role: 'owner',
        tenantId: tenantId,
        tenantName: shopName,
        templateId: 'pharmacy',
        plan: 'free',
        deviceId: deviceId,
        deviceCode: deviceCode,
        deviceLastSeq: deviceLastSeq,
      );

  AuthResult _answer(String call, String deviceId) {
    calls.add(call);
    deviceIds.add(deviceId);
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    return result(deviceId);
  }

  @override
  Future<DateTime> requestOtp(String phone, OtpPurpose purpose) async {
    calls.add('otp:${purpose.name}:$phone');
    return DateTime.now().toUtc().add(const Duration(minutes: 5));
  }

  @override
  Future<AuthResult> login({required String phone, required String pin, required String deviceId, String? deviceName}) async =>
      _answer('login:$phone', deviceId);

  @override
  Future<AuthResult> register({
    required String phone,
    required String otp,
    required String shopName,
    required String templateId,
    String? township,
    required String pin,
    required String deviceId,
    String? deviceName,
  }) async =>
      _answer('register:$phone:$otp:$shopName:$templateId', deviceId);

  @override
  Future<AuthResult> refresh(String refreshToken) async {
    calls.add('refresh:$refreshToken');
    await Future<void>.delayed(refreshDelay);
    final e = refreshError;
    if (e != null) throw e;
    return result('device');
  }

  /// Thrown by resetPin if set.
  ApiError? resetError;

  @override
  Future<void> resetPin({required String phone, required String otp, required String newPin}) async {
    calls.add('reset:$phone');
    if (resetError != null) throw resetError!;
  }
}
