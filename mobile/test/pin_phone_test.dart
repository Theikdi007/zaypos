import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/features/auth/domain/phone.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';

void main() {
  group('PinHasher', () {
    const fast = PinHasher(iterations: 1000, useIsolate: false);

    test('verifies the right PIN only', () async {
      final h = await fast.hash('123456');
      expect(await fast.verify('123456', h), isTrue);
      expect(await fast.verify('123457', h), isFalse);
      expect(await fast.verify('', h), isFalse);
      expect(h, isNot(contains('123456')));
    });

    test('random salt: two hashes of one PIN differ, both verify', () async {
      final a = await fast.hash('000000'), b = await fast.hash('000000');
      expect(a, isNot(b));
      expect(await fast.verify('000000', a) && await fast.verify('000000', b), isTrue);
    });

    test('the iteration count is read from the stored hash', () async {
      final h = await const PinHasher(iterations: 10, useIsolate: false).hash('111111');
      expect(h.split(r'$')[1], '10');
      expect(await fast.verify('111111', h), isTrue);
    });

    test('malformed hashes never verify', () async {
      for (final bad in ['', 'x', r'md5$1$a$b', r'pbkdf2-sha256$0$AA==$AA==', r'pbkdf2-sha256$-5$AA==$AA==']) {
        expect(await fast.verify('123456', bad), isFalse, reason: bad);
      }
    });

    test('default: PBKDF2-SHA256, 100k iterations, 16-byte salt, 32-byte key, on an isolate', () async {
      const real = PinHasher();
      final h = await real.hash('246810');
      final parts = h.split(r'$');
      expect(parts[0], 'pbkdf2-sha256');
      expect(parts[1], '100000');
      expect(Uri.parse('data:;base64,${parts[2]}').data!.contentAsBytes(), hasLength(16));
      expect(Uri.parse('data:;base64,${parts[3]}').data!.contentAsBytes(), hasLength(32));
      expect(await real.verify('246810', h), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('normalizeMmPhone (same rules as the server)', () {
    test('accepts 09…, 9…, 959…, +959… with spaces/dashes and Myanmar digits', () {
      for (final input in ['09 711 234 567', '0971234567','9 712 345 67', '959712345 67', '+95 9-712-345-67', '၀၉၇၁၂၃၄၅၆၇']) {
        expect(normalizeMmPhone(input), startsWith('+959'), reason: input);
      }
      expect(normalizeMmPhone('09 7123 4567'), '+95971234567');
      expect(normalizeMmPhone('9 7123 4567'), '+95971234567');
    });

    test('rejects other numbers', () {
      for (final input in ['', '12345', '08123456789', '09123', '091234567890', 'abc', '+66812345678']) {
        expect(normalizeMmPhone(input), isNull, reason: input);
      }
    });

    test('PIN is exactly 6 digits', () {
      expect(isValidPin('123456'), isTrue);
      for (final p in ['12345', '1234567', '12345a', '']) {
        expect(isValidPin(p), isFalse, reason: p);
      }
    });
  });
}
