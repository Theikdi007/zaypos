// BUG-62: the expiry picker's keyboard-entry field accepts the phone keyboard's 0–9 (and ၀–၉), day first.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/widgets/date_picker.dart';

void main() {
  test('0–9 and ၀–၉, with / - or . between, day first', () {
    final want = DateTime(2030, 11, 28);
    for (final s in ['28/11/2030', '၂၈/၁၁/၂၀၃၀', '28-11-2030', '28.11.2030', ' 28 / 11 / 2030 ', '၂၈-11-2030']) {
      expect(parseTypedDate(s), want, reason: s);
    }
    expect(parseTypedDate('1/2/2031'), DateTime(2031, 2, 1));
  });

  test('impossible dates and anything else are refused (the picker then says "ဖော်မက် မမှန်ကန်ပါ။")', () {
    for (final s in [null, '', '31/02/2030', '28/13/2030', '00/11/2030', '2030/11/28', '28/11/30', 'abc', '28//11/2030']) {
      expect(parseTypedDate(s), isNull, reason: '$s');
    }
  });

  test('the field hint is Burmese, not "dd-mm-yyyy"', () {
    expect(datePickerFieldHint, isNot(contains('dd')));
    expect(RegExp(r'[က-႟]').hasMatch(datePickerFieldHint), isTrue);
  });
}
