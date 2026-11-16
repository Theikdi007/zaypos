import 'package:flutter/material.dart';

/// The picker's Burmese button texts (BUG-54). Flutter's Burmese ("my")
/// localization draws the calendar in Burmese but keeps "OK" in English.
const datePickerConfirmText = 'ရွေးမယ်';
const datePickerCancelText = 'မလုပ်တော့';

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
    );
