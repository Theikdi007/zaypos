import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/api/api_error.dart';
import '../../../core/db/local_data.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/utils/ids.dart';
import '../data/auth_api.dart';
import '../data/boot_state.dart';
import '../data/session.dart';
import '../data/session_store.dart';
import '../domain/phone.dart';
import '../domain/pin_hasher.dart';

enum AuthStatus {
  /// No session: Login / Register only.
  signedOut,

  /// A session exists; the PIN unlocks it offline.
  locked,

  unlocked,
}

class AuthState {
  const AuthState(this.status, {this.notice});
  final AuthStatus status;

  /// Shown on the Login screen after a sign-out (why, and unpushed units).
  final String? notice;
}

/// A user-facing failure: [message] is Burmese, [code] is stable.
class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message, {this.retryAfter});
  final String code;
  final String message;
  final Duration? retryAfter;

  factory AuthFailure.fromApi(ApiError e) => AuthFailure(e.code, e.message, retryAfter: e.retryAfter);

  @override
  String toString() => 'AuthFailure($code)';
}

abstract final class AuthMessages {
  static const badPhone = 'ဖုန်းနံပါတ် မှန်အောင် ထည့်ပါ (ဥပမာ 9 7xx xxx xxx)။';
  static const badPin = 'PIN ၆ လုံး ထည့်ပါ။';

  static String outboxBlocks(int n) =>
      'ဒီဖုန်းမှာ server ကို မပို့ရသေးတဲ့ စာရင်း ${mmNumber(n)} ခု ရှိနေပါတယ်။ '
      'တခြားဆိုင်နဲ့ ဝင်ရင် ဒီစာရင်းတွေ ပျောက်သွားမှာမို့ ခွင့်မပြုပါ။ '
      'မူလဆိုင်နဲ့ ပြန်ဝင်ပြီး sync လုပ်ပြီးမှ ပြောင်းပါ။';

  static String outboxKept(int n) =>
      'မပို့ရသေးတဲ့ စာရင်း ${mmNumber(n)} ခု ဒီဖုန်းထဲမှာ သိမ်းထားပါတယ်။ ဒီဆိုင်နဲ့ ပြန်ဝင်ရင် ဆက်ပို့ပေးပါမယ်။';

  static String wrongPin(int left) => 'PIN မှားနေပါတယ်။ နောက်ထပ် ${mmNumber(left)} ကြိမ် ကြိုးစားလို့ရပါတယ်။';

  static String locked(Duration left) =>
      'PIN မှားတာ များသွားလို့ ${mmNumber(minutesUp(left))} မိနစ် ပိတ်ထားပါတယ်။';

  static const demoUnavailable = 'Demo ဆိုင်ကို debug build မှာပဲ သုံးလို့ရပါတယ်။';
}

/// Sign-in, registration, offline PIN unlock and sign-out (§6).
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final boot = ref.watch(bootStateProvider);
    if (boot.startUnlocked) return const AuthState(AuthStatus.unlocked);
    return AuthState(boot.session == null ? AuthStatus.signedOut : AuthStatus.locked);
  }

  AuthApi get _api => ref.read(authApiProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);
  LocalData get _local => ref.read(localDataProvider);
  DateTime _now() => ref.read(clockProvider)();

  static String get _deviceName => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.android => 'Android',
        _ => defaultTargetPlatform.name,
      };

  static String _phone(String raw) => normalizeMmPhone(raw) ?? (throw const AuthFailure('validation', AuthMessages.badPhone));

  static void _pin(String pin) {
    if (!isValidPin(pin)) throw const AuthFailure('validation', AuthMessages.badPin);
  }

  /// Refuses (before any network call) when signing in would replace local
  /// data while the outbox still has units.
  Future<SignInCheck> _guard(String? phone) async {
    final check = await _local.check(phone);
    if (check == SignInCheck.refuse) {
      throw AuthFailure('outbox_not_empty', AuthMessages.outboxBlocks(await _local.pendingUnits()));
    }
    return check;
  }

  /// Runs [call] with this install's device id. `device_conflict` (the id is
  /// registered to another shop) is retried once with a new id, but only
  /// when the local data is being replaced anyway.
  Future<AuthResult> _withDevice(SignInCheck check, Future<AuthResult> Function(String deviceId) call) async {
    try {
      return await call(ref.read(deviceIdProvider));
    } on ApiError catch (e) {
      if (e.code == 'device_conflict' && check == SignInCheck.replace) {
        try {
          return await call(await ref.read(deviceIdProvider.notifier).replace());
        } on ApiError catch (e2) {
          throw AuthFailure.fromApi(e2);
        }
      }
      throw AuthFailure.fromApi(e);
    }
  }

  /// Register step 1: SMS code. For a new shop the local-data guard runs first.
  Future<DateTime> requestOtp(String rawPhone, OtpPurpose purpose) async {
    final phone = _phone(rawPhone);
    if (purpose == OtpPurpose.register) await _guard(null);
    try {
      return await _api.requestOtp(phone, purpose);
    } on ApiError catch (e) {
      throw AuthFailure.fromApi(e);
    }
  }

  Future<void> login(String rawPhone, String pin) async {
    final phone = _phone(rawPhone);
    _pin(pin);
    final check = await _guard(phone);
    final r = await _withDevice(
        check, (id) => _api.login(phone: phone, pin: pin, deviceId: id, deviceName: _deviceName));
    await _adopt(r, phone, pin);
  }

  Future<void> register({
    required String rawPhone,
    required String otp,
    required String shopName,
    required String templateId,
    required String pin,
  }) async {
    final phone = _phone(rawPhone);
    _pin(pin);
    if (shopName.trim().isEmpty) throw const AuthFailure('validation', 'ဆိုင်အမည် ထည့်ပါ။');
    final check = await _guard(null);
    final r = await _withDevice(
      check,
      (id) => _api.register(
        phone: phone,
        otp: otp.trim(),
        shopName: shopName.trim(),
        templateId: templateId,
        pin: pin,
        deviceId: id,
        deviceName: _deviceName,
      ),
    );
    await _adopt(r, phone, pin);
  }

  /// The server accepted the sign-in: make the local DB this shop's
  /// (wiping other data), then store the session. If the outbox blocks the
  /// wipe, the tokens are dropped and nothing is stored.
  Future<void> _adopt(AuthResult r, String phone, String pin) async {
    try {
      await _local.adopt(
        tenantId: r.tenantId,
        phone: phone,
        shopName: r.tenantName,
        templateId: r.templateId,
        plan: r.plan,
        deviceId: r.deviceId,
        deviceCode: r.deviceCode,
        deviceLastSeq: r.deviceLastSeq,
      );
    } on OutboxNotEmptyException catch (e) {
      throw AuthFailure('outbox_not_empty', AuthMessages.outboxBlocks(e.pending));
    }
    final hash = await ref.read(pinHasherProvider).hash(pin);
    await _store.save(r, phone: phone, pinHash: hash);
    // A replaced database needs its first full download before the app opens (§5.4).
    ref.read(firstSyncDoneProvider.notifier).set(await _local.db.readState(SyncStateKeys.initialSyncDone) == 'true');
    ref.read(sessionProvider.notifier).set(ShopSession(
          tenantId: r.tenantId,
          shopName: r.tenantName,
          templateId: r.templateId,
          userId: r.userId,
          phone: phone,
          role: r.role,
          startedAt: nowUtc(),
        ));
    state = const AuthState(AuthStatus.unlocked);
  }

  /// Time left on the local PIN lockout, if locked.
  Future<Duration?> lockRemaining() async {
    final (_, until) = await _store.pinLock();
    if (until == null) return null;
    final left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  /// Offline unlock: the PIN against the local PBKDF2 hash. 5 wrong → 15 min.
  Future<void> unlock(String pin) async {
    final left = await lockRemaining();
    if (left != null) throw AuthFailure('pin_locked', AuthMessages.locked(left), retryAfter: left);
    final session = await _store.load();
    if (session == null) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    if (isValidPin(pin) && await ref.read(pinHasherProvider).verify(pin, session.pinHash)) {
      await _store.savePinLock(0, null);
      state = const AuthState(AuthStatus.unlocked);
      return;
    }
    final (failures, _) = await _store.pinLock();
    final n = failures + 1;
    if (n >= PinRules.maxFailures) {
      await _store.savePinLock(0, _now().add(PinRules.lockout));
      throw AuthFailure('pin_locked', AuthMessages.locked(PinRules.lockout), retryAfter: PinRules.lockout);
    }
    await _store.savePinLock(n, null);
    throw AuthFailure('pin_wrong', AuthMessages.wrongPin(PinRules.maxFailures - n));
  }

  /// Ends the session. The local database — and the outbox — are kept; the
  /// Login screen warns when units are still waiting.
  Future<void> signOut({String? reasonCode}) async {
    await _store.clear();
    final pending = await _local.pendingUnits();
    ref.read(sessionProvider.notifier).set(ShopSession(tenantId: '', shopName: '', startedAt: nowUtc()));
    final notice = [
      if (reasonCode != null) apiErrorMessage(reasonCode),
      if (pending > 0) AuthMessages.outboxKept(pending),
    ];
    state = AuthState(AuthStatus.signedOut, notice: notice.isEmpty ? null : notice.join('\n'));
  }

  /// The server refused the refresh token (401/403, e.g. `device_revoked`).
  Future<void> sessionEnded(String code) => signOut(reasonCode: code);

  /// Debug builds only: the offline sample shop (never synced).
  Future<void> openDemo() async {
    if (ref.read(isReleaseBuildProvider)) throw const AuthFailure('demo_unavailable', AuthMessages.demoUnavailable);
    // Re-opening the demo keeps its data; replacing a real shop's data follows
    // the sign-in rule (LocalData.adopt refuses while the outbox has units).
    final String tenantId;
    try {
      tenantId = await _local.openDemo(deviceId: ref.read(deviceIdProvider), releaseMode: ref.read(isReleaseBuildProvider));
    } on OutboxNotEmptyException catch (e) {
      throw AuthFailure('outbox_not_empty', AuthMessages.outboxBlocks(e.pending));
    }
    ref.read(sessionProvider.notifier).set(ShopSession(
          tenantId: tenantId,
          shopName: LocalData.demoShopName,
          startedAt: nowUtc(),
          isDemo: true,
        ));
    ref.read(firstSyncDoneProvider.notifier).set(true); // the demo never downloads
    state = const AuthState(AuthStatus.unlocked);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Shared refresher for every authenticated call.
final tokenRefresherProvider = Provider<TokenRefresher>((ref) => TokenRefresher(
      api: ref.watch(authApiProvider),
      store: ref.watch(sessionStoreProvider),
      onSessionEnded: (code) => ref.read(authControllerProvider.notifier).sessionEnded(code),
      clock: ref.watch(clockProvider),
    ));

/// Dio for authenticated `/api/v1` calls (used by sync in Step 3).
final apiDioProvider = Provider<Dio>(
    (ref) => authedDio(ref.watch(apiBaseUrlProvider), ref.watch(tokenRefresherProvider)));
