import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import '../sync/sync_limits.dart' show myanmarDigitsToAscii;

/// The picker's Burmese button texts (BUG-54). Flutter's Burmese ("my")
/// localization draws the calendar in Burmese but keeps "OK" in English.
const datePickerConfirmText = 'ရွေးမယ်';
const datePickerCancelText = 'မလုပ်တော့';

/// Hint of the keyboard-entry field (Flutter's Burmese one is the English "dd-mm-yyyy").
const datePickerFieldHint = 'ရက်/လ/နှစ်';

/// A typed date, day first like the pre-filled value: "28/11/2030", "၂၈/၁၁/၂၀၃၀", "28-11-2030",
/// "28.11.2030" (BUG-62: the phone keyboard types 0–9, Flutter's Burmese parser took only ၀–၉).
/// null for anything else, including dates that don't exist (31/02/2030).
DateTime? parseTypedDate(String? input) {
  final m = RegExp(r'^(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4})$')
      .firstMatch(myanmarDigitsToAscii((input ?? '').trim()));
  if (m == null) return null;
  final (d, mo, y) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final date = DateTime(y, mo, d);
  return date.year == y && date.month == mo && date.day == d ? date : null;
}

/// The expiry-date picker used by Add / Edit Product and "Stock ဖြည့်မယ်":
/// Burmese title, months, digits and buttons.
Future<DateTime?> showExpiryDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) =>
    showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'သက်တမ်းကုန်ရက် ရွေးပါ',
      confirmText: datePickerConfirmText,
      cancelText: datePickerCancelText,
      fieldHintText: datePickerFieldHint,
      builder: (context, child) => Localizations.override(
        context: context,
        delegates: const [_TypedDateLocalizations.delegate],
        child: child,
      ),
    );

/// Burmese Material texts, but the keyboard-entry field also accepts 0–9 (see [parseTypedDate]).
class _TypedDateLocalizations extends MaterialLocalizationMy {
  _TypedDateLocalizations()
      : super(
          fullYearFormat: intl.DateFormat.y(_locale),
          compactDateFormat: intl.DateFormat.yMd(_locale),
          shortDateFormat: intl.DateFormat.yMMMd(_locale),
          mediumDateFormat: intl.DateFormat.MMMEd(_locale),
          longDateFormat: intl.DateFormat.yMMMMEEEEd(_locale),
          yearMonthFormat: intl.DateFormat.yMMMM(_locale),
          shortMonthDayFormat: intl.DateFormat.MMMd(_locale),
          decimalFormat: intl.NumberFormat.decimalPattern(_locale),
          twoDigitZeroPaddedFormat: intl.NumberFormat('00', _locale),
        );

  static const _locale = 'my';
  static const delegate = _TypedDateDelegate();

  @override
  DateTime? parseCompactDate(String? inputString) => parseTypedDate(inputString) ?? super.parseCompactDate(inputString);

  @override
  String get dateHelpText => datePickerFieldHint;
}

class _TypedDateDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _TypedDateDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'my';

  @override
  Future<MaterialLocalizations> load(Locale locale) async => _TypedDateLocalizations();

  @override
  bool shouldReload(_TypedDateDelegate old) => false;
}
