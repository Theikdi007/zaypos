import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Offline PIN check (§6): PBKDF2-HMAC-SHA256, random 16-byte salt, 100k
/// iterations, 256-bit key. Stored as
/// `pbkdf2-sha256$<iterations>$<salt b64>$<key b64>` so the cost can rise later.
class PinHasher {
  const PinHasher({this.iterations = defaultIterations, this.useIsolate = true});

  static const defaultIterations = 100000;

  final int iterations;

  /// Derive on a background isolate (keeps the PIN pad responsive).
  final bool useIsolate;

  Future<String> hash(String pin) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _derive(pin, salt, iterations);
    return 'pbkdf2-sha256\$$iterations\$${base64Encode(salt)}\$${base64Encode(key)}';
  }

  /// Constant-time compare of [pin] against a stored [hash].
  Future<bool> verify(String pin, String hash) async {
    final parts = hash.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final n = int.tryParse(parts[1]);
    if (n == null || n <= 0) return false;
    final expected = base64Decode(parts[3]);
    final actual = await _derive(pin, base64Decode(parts[2]), n);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  Future<List<int>> _derive(String pin, List<int> salt, int n) =>
      useIsolate ? Isolate.run(() => _deriveNow(pin, salt, n)) : _deriveNow(pin, salt, n);

  static Future<List<int>> _deriveNow(String pin, List<int> salt, int n) async {
    final kdf = DartPbkdf2(macAlgorithm: DartHmac.sha256(), iterations: n, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }
}

/// Local lockout: 5 wrong PINs → 15 minutes (§6).
abstract final class PinRules {
  static const maxFailures = 5;
  static const lockout = Duration(minutes: 15);
}

/// Tests override with a cheap hasher (few iterations, no isolate).
final pinHasherProvider = Provider<PinHasher>((_) => const PinHasher());
