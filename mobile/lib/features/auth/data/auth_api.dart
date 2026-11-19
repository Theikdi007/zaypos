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

/// One shop of a Google account (`POST /auth/google/shops`).
class GoogleShop {
  const GoogleShop({required this.tenantId, required this.name, required this.templateId, this.role = 'owner'});
  final String tenantId;
  final String name;
  final String templateId;
  final String role;

  factory GoogleShop.fromJson(Map<String, dynamic> j) => GoogleShop(
        tenantId: j['tenantId'] as String,
        name: j['name'] as String? ?? '',
        templateId: j['templateId'] as String? ?? 'grocery',
        role: j['role'] as String? ?? 'owner',
      );
}

/// "Who is this user": the Google account's email and its shops, oldest first.
class GoogleShops {
  const GoogleShops({this.email, required this.shops});
  final String? email;
  final List<GoogleShop> shops;

  factory GoogleShops.fromJson(Map<String, dynamic> j) => GoogleShops(
        email: j['email'] as String?,
        shops: [for (final s in (j['shops'] as List? ?? const [])) GoogleShop.fromJson(s as Map<String, dynamic>)],
      );
}

/// `/api/v1/auth/*`. Every method throws [ApiError] on failure.
abstract interface class AuthApi {
  /// `POST /auth/google/shops`.
  Future<GoogleShops> googleShops(String idToken);

  /// `POST /auth/google`: a shop of this Google account ([tenantId]) plus the user's PIN. This is the
  /// only way a new phone signs in (there is no phone + PIN sign-in).
  Future<AuthResult> googleSignIn({
    required String idToken,
    required String tenantId,
    required String pin,
    required String deviceId,
    String? deviceName,
  });

  /// `POST /auth/google/register`. [ownerPhone] is a contact number (not verified).
  Future<AuthResult> googleRegister({
    required String idToken,
    required String shopName,
    required String templateId,
    String? township,
    required String ownerPhone,
    required String pin,
    required String deviceId,
    String? deviceName,
  });

  /// `POST /auth/google/pin/reset`: every session of the user ends.
  Future<void> googleResetPin({required String idToken, required String tenantId, required String newPin});

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

  Future<AuthResult> refresh(String refreshToken);
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
  Future<GoogleShops> googleShops(String idToken) async =>
      GoogleShops.fromJson(await _post('/google/shops', {'idToken': idToken}));

  @override
  Future<AuthResult> googleSignIn({
    required String idToken,
    required String tenantId,
    required String pin,
    required String deviceId,
    String? deviceName,
  }) async =>
      AuthResult.fromJson(await _post('/google', {
        'idToken': idToken,
        'tenantId': tenantId,
        'pin': pin,
        'device': _device(deviceId, deviceName),
      }));

  @override
  Future<AuthResult> googleRegister({
    required String idToken,
    required String shopName,
    required String templateId,
    String? township,
    required String ownerPhone,
    required String pin,
    required String deviceId,
    String? deviceName,
  }) async =>
      AuthResult.fromJson(await _post('/google/register', {
        'idToken': idToken,
        'shopName': shopName,
        'templateId': templateId,
        'township': township,
        'ownerPhone': ownerPhone,
        'pin': pin,
        'device': _device(deviceId, deviceName),
      }));

  @override
  Future<void> googleResetPin({required String idToken, required String tenantId, required String newPin}) async {
    await _post('/google/pin/reset', {'idToken': idToken, 'tenantId': tenantId, 'newPin': newPin});
  }

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
  Future<AuthResult> refresh(String refreshToken) async =>
      AuthResult.fromJson(await _post('/refresh', {'refreshToken': refreshToken}));
}

/// Dio for anonymous calls (auth, limits). Every dio in the app is built here
/// (or by [authedDio] on top of it), so the release HTTPS guard (BUG-55) is on
/// every request.
Dio plainDio(String baseUrl, {bool? release}) => Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ))
      ..interceptors.add(release == null ? HttpsOnlyInterceptor() : HttpsOnlyInterceptor(release: release));

final authApiProvider = Provider<AuthApi>((ref) => DioAuthApi(plainDio(ref.watch(apiBaseUrlProvider))));
