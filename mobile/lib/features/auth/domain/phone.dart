export '../../../core/utils/phone.dart' show normalizeMmPhone, phoneDigits, phoneKey, phoneSearchKey, samePhone;

/// The PIN pad takes exactly 6 digits.
bool isValidPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);
