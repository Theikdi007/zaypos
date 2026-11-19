import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_failure.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';

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

  // ── Google ──────────────────────────────────────────────────────────────

  /// What `/google/shops` answers (the Google account's shops).
  List<GoogleShop> googleShopList = [];

  /// Thrown by the next googleShops call (then cleared).
  ApiError? shopsError;

  /// The ID tokens the API was given, in order.
  final idTokens = <String>[];

  @override
  Future<GoogleShops> googleShops(String idToken) async {
    calls.add('google:shops');
    idTokens.add(idToken);
    final e = shopsError;
    if (e != null) {
      shopsError = null;
      throw e;
    }
    return GoogleShops(email: 'owner@gmail.com', shops: googleShopList);
  }

  @override
  Future<AuthResult> googleSignIn({
    required String idToken,
    required String tenantId,
    required String pin,
    required String deviceId,
    String? deviceName,
  }) async {
    idTokens.add(idToken);
    this.tenantId = tenantId;
    return _answer('google:signIn:$tenantId:$pin', deviceId);
  }

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
  }) async {
    idTokens.add(idToken);
    return _answer('google:register:$shopName:$templateId:$ownerPhone:$pin', deviceId);
  }

  /// Thrown by googleResetPin if set.
  ApiError? resetError;

  @override
  Future<void> googleResetPin({required String idToken, required String tenantId, required String newPin}) async {
    calls.add('google:reset:$tenantId:$newPin');
    idTokens.add(idToken);
    if (resetError != null) throw resetError!;
  }
}

/// Stands in for Google's account picker. [next] = what the next signIn does.
class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.email = 'owner@gmail.com'});

  String? email;
  int signIns = 0;
  int signOuts = 0;

  /// Thrown by the next signIn (then cleared), e.g. `AuthFailure('google_cancelled', …)`.
  AuthFailure? nextError;

  @override
  Future<GoogleIdentity> signIn() async {
    signIns++;
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    return GoogleIdentity(idToken: 'google-id-token-$signIns', email: email);
  }

  @override
  Future<void> signOut() async => signOuts++;
}
