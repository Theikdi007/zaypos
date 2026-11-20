import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../application/auth_failure.dart';

/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`: Android puts it in the ID token's `aud`.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// `--dart-define=GOOGLE_IOS_CLIENT_ID=<iOS client id>` (its reversed form is the URL scheme in Info.plist).
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

/// `--dart-define=AUTH_OTP_ENABLED=true` brings back the SMS OTP screens (docs/backend/auth-google.md §4).
const authOtpEnabled = bool.fromEnvironment('AUTH_OTP_ENABLED');

/// Off (default): Google sign-in. On: the old phone + SMS OTP flow. A provider so tests can switch it.
final otpEnabledProvider = Provider<bool>((_) => authOtpEnabled);

/// A Google account the user just picked. [idToken] goes to the API, which verifies it.
class GoogleIdentity {
  const GoogleIdentity({required this.idToken, this.email});
  final String idToken;
  final String? email;
}

abstract final class GoogleMessages {
  static const cancelled = 'Google နဲ့ ဝင်တာကို ရပ်လိုက်ပါတယ်။';
  static const noAccount =
      'ဒီဖုန်းမှာ Google အကောင့် မရှိသေးပါ။ ဖုန်းရဲ့ ဆက်တင်မှာ Google အကောင့် ထည့်ပြီးမှ ပြန်ကြိုးစားပါ။';
  // Google Play services missing or too old.
  static const playServices =
      'ဒီဖုန်းမှာ Google ဝန်ဆောင်မှု မရှိ (သို့) ဗားရှင်းဟောင်း ဖြစ်နေပါတယ်။ Google ဝန်ဆောင်မှုကို အသစ်တင်ပြီးမှ ပြန်ကြိုးစားပါ။';
  static const offline = 'အင်တာနက် မရပါ။ လိုင်းရမှ ပြန်ကြိုးစားပါ။';
  static const failed = 'Google နဲ့ ဝင်လို့ မရပါ။ ခဏနေ ပြန်ကြိုးစားပါ။';
  static const notConfigured = 'ဒီဗားရှင်းမှာ Google နဲ့ ဝင်ဖို့ ပြင်ဆင်ထားခြင်း မရှိသေးပါ။';
}

/// Google's account picker → an ID token. Throws [AuthFailure] with a Burmese message:
/// `google_cancelled`, `google_no_account`, `google_play_services`, `network`, `google_failed`,
/// `google_not_configured`.
abstract interface class GoogleAuth {
  Future<GoogleIdentity> signIn();

  /// Forget the picked account, so the next [signIn] shows the picker again.
  Future<void> signOut();
}

/// [GoogleSignInException] → [AuthFailure]. Pure, so every branch is unit-tested.
AuthFailure googleFailure(GoogleSignInExceptionCode code, String? description, {required bool android}) {
  final d = (description ?? '').toLowerCase();
  if (d.contains('network') || d.contains('offline') || d.contains('internet')) {
    return const AuthFailure('network', GoogleMessages.offline);
  }
  return switch (code) {
    GoogleSignInExceptionCode.canceled => const AuthFailure('google_cancelled', GoogleMessages.cancelled),
    // Android Credential Manager: "No credential available" = no Google account on the phone.
    GoogleSignInExceptionCode.unknownError when d.contains('no credential') =>
      const AuthFailure('google_no_account', GoogleMessages.noAccount),
    // Android: Credential Manager / Play services missing, too old or unsupported.
    GoogleSignInExceptionCode.providerConfigurationError when android =>
      const AuthFailure('google_play_services', GoogleMessages.playServices),
    GoogleSignInExceptionCode.clientConfigurationError =>
      const AuthFailure('google_not_configured', GoogleMessages.notConfigured),
    _ => const AuthFailure('google_failed', GoogleMessages.failed),
  };
}

/// Can this phone reach Google right now? A Wi-Fi without internet still reports "wifi" to
/// connectivity_plus (always so on the iOS simulator), so open a real connection to Google's
/// sign-in host. Without this, iOS opens Google's sheet on Safari's English "Can't Open Page"
/// and reports the closed sheet as a cancel (BUG-69).
Future<bool> canReachGoogle({Duration timeout = const Duration(seconds: 4)}) async {
  if ((await Connectivity().checkConnectivity()).every((r) => r == ConnectivityResult.none)) return false;
  try {
    final socket = await Socket.connect('accounts.google.com', 443, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false; // no DNS, no route, timeout
  }
}

/// The real picker (google_sign_in 7: Credential Manager on Android, GIDSignIn on iOS).
class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth({
    this.serverClientId = googleServerClientId,
    this.iosClientId = googleIosClientId,
    Future<bool> Function()? online,
  }) : _online = online ?? canReachGoogle;

  final String serverClientId;
  final String iosClientId;
  final Future<bool> Function() _online;
  Future<void>? _init;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  bool get _configured => serverClientId.isNotEmpty && (!_ios || iosClientId.isNotEmpty);

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(
        clientId: _ios ? iosClientId : null,
        serverClientId: serverClientId,
      );

  @override
  Future<GoogleIdentity> signIn() async {
    if (!_configured) throw const AuthFailure('google_not_configured', GoogleMessages.notConfigured);
    // Before Google's UI opens: offline gets the Burmese "no internet", not a browser error page.
    if (!await _online()) throw const AuthFailure('network', GoogleMessages.offline);
    try {
      await _ready();
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email']);
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) throw const AuthFailure('google_failed', GoogleMessages.failed);
      return GoogleIdentity(idToken: token, email: account.email);
    } on AuthFailure {
      rethrow;
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      // iOS: the internet dropped while the sheet was open, the page failed, the user closed it,
      // and the plugin says "canceled". Say what really happened.
      if (e.code == GoogleSignInExceptionCode.canceled && !await _online()) {
        throw const AuthFailure('network', GoogleMessages.offline);
      }
      throw googleFailure(e.code, e.description, android: _android);
    } catch (e) {
      // PlatformException etc.: e.g. no Play services at all on the device.
      debugPrint('Google sign-in failed: $e');
      final s = e.toString().toLowerCase();
      if (_android && (s.contains('play services') || s.contains('gms'))) {
        throw const AuthFailure('google_play_services', GoogleMessages.playServices);
      }
      throw const AuthFailure('google_failed', GoogleMessages.failed);
    }
  }

  @override
  Future<void> signOut() async {
    if (!_configured || _init == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to forget.
    }
  }
}

final googleAuthProvider = Provider<GoogleAuth>((_) => PluginGoogleAuth());
