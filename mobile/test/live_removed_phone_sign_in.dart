// Live tests only (skipped unless ZAYPOS_LIVE_* is set).
//
// Phone + PIN sign-in (POST /auth/login) and the SMS PIN reset were removed: a new phone signs in only
// with Google + the shop + the PIN, and the PIN alone only unlocks a phone that is already signed in
// (docs/backend/auth-google.md §3). These live tests registered a shop by SMS and then signed a second
// phone in by phone + PIN. Those steps now stop with [removedPhoneSignIn]; rewriting them for Google
// needs a real Google ID token for the local API. The steps before them (register by SMS with
// AUTH_OTP_ENABLED, one phone, sync) still run.
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';

const removedPhoneSignIn =
    'Phone + PIN sign-in was removed (Google only, docs/backend/auth-google.md §3); this live step needs a rewrite for Google sign-in.';

extension RemovedPhoneSignIn on AuthController {
  Future<void> login(String phone, String pin) async => throw UnsupportedError(removedPhoneSignIn);

  Future<void> resetPin({required String rawPhone, required String otp, required String newPin}) async =>
      throw UnsupportedError(removedPhoneSignIn);
}

extension RemovedPhoneSignInApi on AuthApi {
  Future<AuthResult> login({required String phone, required String pin, required String deviceId, String? deviceName}) async =>
      throw UnsupportedError(removedPhoneSignIn);
}
