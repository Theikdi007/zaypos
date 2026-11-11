import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/qty.dart';

void main() {
  group('Qty.parse', () {
    test('whole numbers', () {
      expect(Qty.parse('3', decimal: false), 3000);
      expect(Qty.parse(' 48 ', decimal: false), 48000);
      expect(Qty.parse('0', decimal: false), 0);
    });
    test('decimals only when decimalQty is on', () {
      expect(Qty.parse('2.5', decimal: false), isNull);
      expect(Qty.parse('2.5', decimal: true), 2500);
      expect(Qty.parse('0.75', decimal: true), 750);
      expect(Qty.parse('1.005', decimal: true), 1005);
      expect(Qty.parse('3.', decimal: true), 3000);
    });
    test('no floating-point drift', () {
      expect(Qty.parse('0.1', decimal: true)! + Qty.parse('0.2', decimal: true)!, 300);
    });
    test('rejects invalid input', () {
      for (final s in ['', 'abc', '-1', '1.2345', '1,000', '.5']) {
        expect(Qty.parse(s, decimal: true), isNull, reason: s);
      }
    });
  });

  group('Qty.format', () {
    test('trims trailing zeros', () {
      expect(Qty.format(2500), '2.5');
      expect(Qty.format(3000), '3');
      expect(Qty.format(750), '0.75');
      expect(Qty.format(1005), '1.005');
      expect(Qty.format(0), '0');
      expect(Qty.format(-1500), '-1.5');
    });
    test('round-trips', () {
      for (final m in [0, 1, 250, 1000, 2500, 123456]) {
        expect(Qty.parse(Qty.format(m), decimal: true), m);
      }
    });
  });

  group('Qty.lineTotal', () {
    test('price × qty in kyats', () {
      expect(Qty.lineTotal(600, 2000), 1200);
      expect(Qty.lineTotal(1200, 2500), 3000); // 2.5 ft × 1,200
    });
    test('rounds half up to whole kyats', () {
      expect(Qty.lineTotal(333, 1500), 500); // 499.5 -> 500
      expect(Qty.lineTotal(333, 1499), 499); // 499.167 -> 499
    });
    test('negative amounts round symmetrically', () {
      expect(Qty.lineTotal(-100, 1000), -100);
      expect(Qty.lineTotal(-333, 1500), -500);
      expect(Qty.lineTotal(-333, 1499), -499);
    });
  });
}
