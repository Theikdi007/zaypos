import 'package:flutter/services.dart';

/// Turns Myanmar digits ၀-၉ (U+1040–U+1049) into 0-9 as they are typed or
/// pasted (BUG-41), so the ASCII-only filters after it keep them instead of
/// dropping them. Each digit is one UTF-16 unit both ways, so the cursor and
/// selection stay where they were.
class MyanmarDigitsToAscii extends TextInputFormatter {
  const MyanmarDigitsToAscii();

  static final _mm = RegExp('[၀-၉]');

  static String convert(String s) =>
      s.replaceAllMapped(_mm, (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x1040 + 0x30));

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!_mm.hasMatch(newValue.text)) return newValue;
    return newValue.copyWith(text: convert(newValue.text));
  }
}

/// OTP / PIN fields: Myanmar digits become 0-9, anything else is dropped, at most [maxLength].
List<TextInputFormatter> digitInput({int? maxLength}) => [
      const MyanmarDigitsToAscii(),
      FilteringTextInputFormatter.digitsOnly,
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];

/// Phone fields: Myanmar digits become 0-9; digits and spaces are kept.
List<TextInputFormatter> phoneInput() => [
      const MyanmarDigitsToAscii(),
      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
    ];
