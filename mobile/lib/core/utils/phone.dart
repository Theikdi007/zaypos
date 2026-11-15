/// The one phone normalizer (BUG-34). Every place that compares or searches
/// phone numbers goes through [phoneKey]: the duplicate-phone warning, the stored
/// side of customer search and OTP sign-in ([normalizeMmPhone] builds on it). A
/// search QUERY is partial and goes through [phoneSearchKey] instead (BUG-36).
///
/// Myanmar digits → 0-9, spaces/dashes/dots/brackets dropped, and the
/// international forms +959… / 959… written as 09…:
/// "+95 9-790.011 ၀၀၂" → "09790011002". Anything else (a landline, a partial
/// number typed into search) is returned with only those steps applied.
String phoneKey(String? input) {
  final s = phoneDigits(input);
  if (s.startsWith('+959')) return '09${s.substring(4)}';
  if (s.startsWith('959')) return '09${s.substring(3)}';
  return s;
}

/// Only the digit steps of [phoneKey]: Myanmar digits → 0-9, spaces/dashes/dots/brackets dropped. No prefix rewrite.
String phoneDigits(String? input) {
  if (input == null) return '';
  final s = input.trim().replaceAllMapped(RegExp('[၀-၉]'), (m) => (m[0]!.codeUnitAt(0) - 0x1040).toString());
  return s.replaceAll(RegExp(r'[\s\-().]'), '');
}

/// A customer-search query (BUG-36): a partial number, so a leading "959" is just digits ("959123" is the end of
/// "09 777 959 123") and is NOT rewritten as "09". Only an explicit "+95" becomes "0" ("+95977" → "0977"), so the
/// query can be matched against [phoneKey] of the stored phone.
String phoneSearchKey(String? input) {
  final s = phoneDigits(input);
  return s.startsWith('+95') ? '0${s.substring(3)}' : s;
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
