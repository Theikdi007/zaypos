// QA round 19 (BUG-69 / TC-GAUTH-NEW-3, TC-GAUTH-09 iOS offline): the second half of the fix. The developer's unit test
// (test/google_auth_test.dart "BUG-69: …") covers "offline before the sheet opens". These cover what iOS really did in
// round 18: the sheet opened, the page failed, the user closed it and the plugin said "canceled". With Google
// unreachable at that moment the user must get the Burmese no-internet message; when Google is reachable a cancel is
// still a cancel. The Google plugin is faked at its platform interface (no real Google, no network).
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:zaypos_app/features/auth/application/auth_failure.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';

class _CancelingPlatform extends GoogleSignInPlatform {
  int authenticateCalls = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) =>
      null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    authenticateCalls++;
    throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled, description: 'The user canceled');
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  late _CancelingPlatform platform;

  setUp(() {
    platform = _CancelingPlatform();
    GoogleSignInPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('TC-GAUTH-NEW-3 / BUG-69: iOS sheet opened, internet dropped, sheet closed ("canceled") → no-internet message',
      () async {
    var probes = 0;
    final g = PluginGoogleAuth(serverClientId: 'web', iosClientId: 'ios', online: () async => ++probes == 1);
    await expectLater(
      g.signIn(),
      throwsA(isA<AuthFailure>()
          .having((f) => f.code, 'code', 'network')
          .having((f) => f.message, 'message', 'အင်တာနက် မရပါ။ လိုင်းရမှ ပြန်ကြိုးစားပါ။')),
    );
    expect(platform.authenticateCalls, 1, reason: 'online at the start: Google sheet was opened once');
    expect(probes, 2, reason: 're-probed after the cancel');
  });

  test('TC-GAUTH-09: a real cancel while online is still the cancelled message, not "no internet"', () async {
    final g = PluginGoogleAuth(serverClientId: 'web', iosClientId: 'ios', online: () async => true);
    await expectLater(
      g.signIn(),
      throwsA(isA<AuthFailure>()
          .having((f) => f.code, 'code', isNot('network'))
          .having((f) => f.message, 'message', 'Google နဲ့ ဝင်တာကို ရပ်လိုက်ပါတယ်။')),
    );
  });
}
