import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key/value secrets (Keychain / Android Keystore-backed storage).
abstract interface class SecureStore {
  Future<String?> read(String key);

  /// null deletes the key.
  Future<void> write(String key, String? value);
  Future<Map<String, String>> readAll();
  Future<void> deleteAll();
}

/// docs/mobile/phase3-sync.md §6.
abstract final class SecureKeys {
  static const refreshToken = 'refreshToken';
  static const refreshExpiresAt = 'refreshExpiresAt';
  static const accessToken = 'accessToken';
  static const accessExpiresAt = 'accessExpiresAt';
  static const pinHash = 'pinHash';
  static const pinFailures = 'pinFailures';
  static const pinLockedUntil = 'pinLockedUntil';
  static const tenantId = 'tenantId';
  static const userId = 'userId';
  static const deviceId = 'deviceId';
  static const deviceCode = 'deviceCode';
  static const phone = 'phone';
  static const shopName = 'shopName';
  static const templateId = 'templateId';
  static const role = 'role';
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore([this._s = const FlutterSecureStorage()]);
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);

  @override
  Future<Map<String, String>> readAll() => _s.readAll();

  @override
  Future<void> deleteAll() => _s.deleteAll();
}

/// In-memory store (tests).
class MemorySecureStore implements SecureStore {
  MemorySecureStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> deleteAll() async => values.clear();
}

/// Bound in main.dart (tests: MemorySecureStore).
final secureStoreProvider = Provider<SecureStore>((_) => MemorySecureStore());
