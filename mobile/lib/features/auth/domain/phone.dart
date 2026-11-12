/// Myanmar mobile number → E.164, same rules as the server's
/// `PhoneNumbers.Normalize`: accepts 09…, 9… (typed after the +95 prefix the
/// field shows), 959… and +959…, with spaces/dashes. Myanmar digits are
/// accepted. Returns null when invalid.
String? normalizeMmPhone(String? input) {
  if (input == null) return null;
  var s = input.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  s = s.replaceAllMapped(RegExp('[၀-၉]'), (m) => (m[0]!.codeUnitAt(0) - 0x1040).toString());
  if (s.startsWith('+959')) {
    s = s.substring(4);
  } else if (s.startsWith('959')) {
    s = s.substring(3);
  } else if (s.startsWith('09')) {
    s = s.substring(2);
  } else if (s.startsWith('9')) {
    s = s.substring(1);
  } else {
    return null;
  }
  return RegExp(r'^\d{7,9}$').hasMatch(s) ? '+959$s' : null;
}

/// The PIN pad takes exactly 6 digits.
bool isValidPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);
