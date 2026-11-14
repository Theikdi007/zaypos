import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_store.dart';
import 'auth_api.dart';

/// A signed-in session as kept in secure storage (§6).
class StoredSession {
  const StoredSession({
    required this.tenantId,
    required this.userId,
    required this.deviceCode,
    required this.phone,
    required this.shopName,
    required this.templateId,
    required this.role,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.pinHash,
  });

  final String tenantId;
  final String userId;
  final String deviceCode;

  /// E.164.
  final String phone;
  final String shopName;
  final String templateId;
  final String role;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final String pinHash;
}

/// Access / refresh tokens only.
class Tokens {
  const Tokens({required this.access, required this.accessExpiresAt, required this.refresh});
  final String access;
  final DateTime accessExpiresAt;
  final String refresh;
}

/// Reads and writes the session keys of [SecureKeys]. The install's
/// deviceId is NOT part of a session: it survives sign-out.
class SessionStore {
  SessionStore(this.store);
  final SecureStore store;

  static const _sessionKeys = [
    SecureKeys.refreshToken,
    SecureKeys.refreshExpiresAt,
    SecureKeys.accessToken,
    SecureKeys.accessExpiresAt,
    SecureKeys.pinHash,
    SecureKeys.pinFailures,
    SecureKeys.pinLockedUntil,
    SecureKeys.tenantId,
    SecureKeys.userId,
    SecureKeys.deviceCode,
    SecureKeys.phone,
    SecureKeys.shopName,
    SecureKeys.templateId,
    SecureKeys.role,
  ];

  /// null unless every required key is present.
  Future<StoredSession?> load() async {
    final v = await store.readAll();
    String? s(String k) => v[k];
    final tenantId = s(SecureKeys.tenantId), refresh = s(SecureKeys.refreshToken), pin = s(SecureKeys.pinHash);
    if (tenantId == null || refresh == null || pin == null) return null;
    return StoredSession(
      tenantId: tenantId,
      userId: s(SecureKeys.userId) ?? '',
      deviceCode: s(SecureKeys.deviceCode) ?? '',
      phone: s(SecureKeys.phone) ?? '',
      shopName: s(SecureKeys.shopName) ?? '',
      templateId: s(SecureKeys.templateId) ?? 'grocery',
      role: s(SecureKeys.role) ?? 'owner',
      accessToken: s(SecureKeys.accessToken) ?? '',
      accessExpiresAt: DateTime.tryParse(s(SecureKeys.accessExpiresAt) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      refreshToken: refresh,
      pinHash: pin,
    );
  }

  Future<void> save(AuthResult r, {required String phone, required String pinHash}) async {
    await saveTokens(r);
    await store.write(SecureKeys.pinHash, pinHash);
    await store.write(SecureKeys.pinFailures, null);
    await store.write(SecureKeys.pinLockedUntil, null);
    await store.write(SecureKeys.tenantId, r.tenantId);
    await store.write(SecureKeys.userId, r.userId);
    await store.write(SecureKeys.deviceCode, r.deviceCode);
    await store.write(SecureKeys.phone, phone);
    await store.write(SecureKeys.shopName, r.tenantName);
    await store.write(SecureKeys.templateId, r.templateId);
    await store.write(SecureKeys.role, r.role);
  }

  Future<Tokens?> tokens() async {
    final v = await store.readAll();
    final access = v[SecureKeys.accessToken], refresh = v[SecureKeys.refreshToken];
    if (access == null || refresh == null) return null;
    return Tokens(
      access: access,
      accessExpiresAt: DateTime.tryParse(v[SecureKeys.accessExpiresAt] ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      refresh: refresh,
    );
  }

  Future<void> saveTokens(AuthResult r) async {
    await store.write(SecureKeys.accessToken, r.accessToken);
    await store.write(SecureKeys.accessExpiresAt, r.accessExpiresAt.toIso8601String());
    await store.write(SecureKeys.refreshToken, r.refreshToken);
    await store.write(SecureKeys.refreshExpiresAt, r.refreshExpiresAt.toIso8601String());
  }

  /// Offline unlock attempts (survive app restarts, so killing the app does not reset them).
  Future<(int failures, DateTime? lockedUntil)> pinLock() async => (
        int.tryParse(await store.read(SecureKeys.pinFailures) ?? '') ?? 0,
        DateTime.tryParse(await store.read(SecureKeys.pinLockedUntil) ?? '')?.toUtc(),
      );

  Future<void> savePinLock(int failures, DateTime? lockedUntil) async {
    await store.write(SecureKeys.pinFailures, failures == 0 ? null : '$failures');
    await store.write(SecureKeys.pinLockedUntil, lockedUntil?.toIso8601String());
  }

  /// Sign-out: every session key goes; the install deviceId stays.
  Future<void> clear() async {
    for (final k in _sessionKeys) {
      await store.write(k, null);
    }
  }
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(ref.watch(secureStoreProvider)));
