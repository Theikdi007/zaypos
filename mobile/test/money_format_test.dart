import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/money_format.dart';
import 'package:zaypos_app/core/utils/thousands_formatter.dart';

void main() {
  group('formatMoney / formatKs', () {
    test('groups thousands', () {
      expect(formatMoney(0), '0');
      expect(formatMoney(600), '600');
      expect(formatMoney(245800), '245,800');
      expect(formatMoney(2412600), '2,412,600');
    });
    test('negative', () => expect(formatMoney(-1400), '-1,400'));
    test('Ks suffix', () => expect(formatKs(41200), '41,200 Ks'));
  });

  group('parseMoney', () {
    test('strips separators', () => expect(parseMoney('10,000'), 10000));
    test('empty -> 0', () => expect(parseMoney(''), 0));
  });
}
