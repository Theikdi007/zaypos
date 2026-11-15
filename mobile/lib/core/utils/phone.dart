/// The one phone normalizer (BUG-34). Every place that compares or searches
/// phone numbers goes through [phoneKey]: customer search, the duplicate-phone
/// warning and OTP sign-in ([normalizeMmPhone] builds on it).
///
/// Myanmar digits → 0-9, spaces/dashes/dots/brackets dropped, and the
/// international forms +959… / 959… written as 09…:
/// "+95 9-790.011 ၀၀၂" → "09790011002". Anything else (a landline, a partial
/// number typed into search) is returned with only those steps applied.
String phoneKey(String? input) {
  if (input == null) return '';
  var s = input.trim().replaceAllMapped(RegExp('[၀-၉]'), (m) => (m[0]!.codeUnitAt(0) - 0x1040).toString());
  s = s.replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.startsWith('+959')) return '09${s.substring(4)}';
  if (s.startsWith('959')) return '09${s.substring(3)}';
  return s;
}

/// Same number? Both sides through [phoneKey]; an empty number matches nothing.
bool samePhone(String? a, String? b) {
  final ka = phoneKey(a);
  return ka.isNotEmpty && ka == phoneKey(b);
}

/// Myanmar mobile number → E.164, same rules as the server's
/// `PhoneNumbers.Normalize`: accepts 09…, 9… (typed after the +95 prefix the
/// field shows), 959… and +959…, with spaces/dashes/dots. Myanmar digits are
/// accepted. Returns null when invalid.
String? normalizeMmPhone(String? input) {
  if (input == null) return null;
  final k = phoneKey(input);
  final String sub;
  if (k.startsWith('09')) {
    sub = k.substring(2);
  } else if (k.startsWith('9')) {
    sub = k.substring(1);
  } else {
    return null;
  }
  return RegExp(r'^\d{7,9}$').hasMatch(sub) ? '+959$sub' : null;
}
