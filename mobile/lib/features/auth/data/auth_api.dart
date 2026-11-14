import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/api_error.dart';

/// Server `OtpPurpose` (camelCase on the wire).
enum OtpPurpose { register, reset }

/// Server `AuthResponse` (backend AuthContracts.cs), flattened.
class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.userId,
    required this.userName,
    required this.role,
    required this.tenantId,
    required this.tenantName,
    required this.templateId,
    required this.plan,
    required this.deviceId,
    required this.deviceCode,
    required this.deviceLastSeq,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String userId;
  final String userName;

  /// `owner` | `staff`.
  final String role;
  final String tenantId;
  final String tenantName;
  final String templateId;

  /// `free` | `pro`.
  final String plan;
  final String deviceId;
  final String deviceCode;
  final int deviceLastSeq;

  factory AuthResult.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    final tenant = j['tenant'] as Map<String, dynamic>;
    final device = j['device'] as Map<String, dynamic>;
    return AuthResult(
      accessToken: j['accessToken'] as String,
      accessExpiresAt: DateTime.parse(j['accessTokenExpiresAt'] as String).toUtc(),
      refreshToken: j['refreshToken'] as String,
      refreshExpiresAt: DateTime.parse(j['refreshTokenExpiresAt'] as String).toUtc(),
      userId: user['id'] as String,
      userName: user['name'] as String? ?? '',
      role: user['role'] as String? ?? 'owner',
      tenantId: tenant['id'] as String,
      tenantName: tenant['name'] as String? ?? '',
      templateId: tenant['templateId'] as String? ?? 'grocery',
      plan: tenant['plan'] as String? ?? 'free',
      deviceId: device['id'] as String,
      deviceCode: device['code'] as String,
      deviceLastSeq: (device['lastSeq'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `/api/v1/auth/*`. Every method throws [ApiError] on failure.
abstract interface class AuthApi {
  /// Sends an SMS code; returns when it expires.
  Future<DateTime> requestOtp(String phone, OtpPurpose purpose);

  Future<AuthResult> register({
    required String phone,
    required String otp,
    required String shopName,
    required String templateId,
    String? township,
    required String pin,
    required String deviceId,
    String? deviceName,
  });

  Future<AuthResult> login({required String phone, required String pin, required String deviceId, String? deviceName});

  Future<AuthResult> refresh(String refreshToken);

  Future<void> resetPin({required String phone, required String otp, required String newPin});
}

/// Plain dio (no auth interceptor): these endpoints are anonymous.
class DioAuthApi implements AuthApi {
  DioAuthApi(this.dio);
  final Dio dio;

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) async {
    try {
      final r = await dio.post<Map<String, dynamic>>('/api/v1/auth$path', data: body);
      return r.data ?? const {};
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Map<String, Object?> _device(String id, String? name) => {'id': id, 'name': name};

  @override
  Future<DateTime> requestOtp(String phone, OtpPurpose purpose) async {
    final j = await _post('/otp', {'phone': phone, 'purpose': purpose.name});
    return DateTime.parse(j['expiresAt'] as String).toUtc();
  }

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
      AuthResult.fromJson(await _post('/register', {
        'phone': phone,
        'otp': otp,
        'shopName': shopName,
        'templateId': templateId,
        'township': township,
        'pin': pin,
        'device': _device(deviceId, deviceName),
      }));

  @override
  Future<AuthResult> login({required String phone, required String pin, required String deviceId, String? deviceName}) async =>
      AuthResult.fromJson(await _post('/login', {'phone': phone, 'pin': pin, 'device': _device(deviceId, deviceName)}));

  @override
  Future<AuthResult> refresh(String refreshToken) async =>
      AuthResult.fromJson(await _post('/refresh', {'refreshToken': refreshToken}));

  @override
  Future<void> resetPin({required String phone, required String otp, required String newPin}) async {
    await _post('/pin/reset', {'phone': phone, 'otp': otp, 'newPin': newPin});
  }
}

/// Dio for anonymous calls (auth, limits).
Dio plainDio(String baseUrl) => Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ));

final authApiProvider = Provider<AuthApi>((ref) => DioAuthApi(plainDio(ref.watch(apiBaseUrlProvider))));
