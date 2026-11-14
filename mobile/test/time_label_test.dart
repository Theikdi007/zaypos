import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/myanmar.dart';

/// BUG-9: times are shown with the Burmese time of day, not AM/PM.
void main() {
  String at(int h, int m) => timeLabel(DateTime(2026, 11, 14, h, m));

  test('12-hour clock with နံနက် / နေ့လယ် / ညနေ / ည', () {
    expect(at(0, 5), 'နံနက် 12:05');
    expect(at(9, 5), 'နံနက် 9:05');
    expect(at(11, 59), 'နံနက် 11:59');
    expect(at(12, 0), 'နေ့လယ် 12:00');
    expect(at(15, 42), 'နေ့လယ် 3:42');
    expect(at(16, 0), 'ညနေ 4:00');
    expect(at(18, 59), 'ညနေ 6:59');
    expect(at(19, 0), 'ည 7:00');
    expect(at(23, 30), 'ည 11:30');
  });

  test('no Latin letters in time labels (receipt, debt history)', () {
    final t = DateTime(2026, 11, 10, 16, 5);
    for (final s in [timeLabel(t), mmReceiptDate(t), entryDateLabel(t, t.add(const Duration(days: 3)))]) {
      expect(RegExp('[A-Za-z]').hasMatch(s), isFalse, reason: s);
    }
    expect(mmReceiptDate(t), '၁၀ နိုဝင်ဘာ ၂၀၂၆ · ညနေ 4:05');
  });
}
