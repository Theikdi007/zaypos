import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BUG-9: Burmese UI strings may only contain the owner's English words (2026-11-14):
/// KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP, Stock, Sync, Batch — plus things that are not words:
/// the brand, the currency / units and phone-number placeholders. Product-name examples are data.
const _allowed = {
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch', // batch: owner 2026-11-14 (printed on medicine boxes)
  'zaypos', 'ks', 'ml', 'kg', 'xx', 'xxx',
};
const _examples = {'ဥပမာ - Paracetamol 500mg', 'ဥပမာ - Type-C အားသွင်းကြိုး'};

/// Removes `${…}` (balanced braces, may contain quotes) so code inside strings is not read as text.
String _stripInterpolations(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s.startsWith(r'${', i)) {
      var depth = 1;
      i += 2;
      while (i < s.length && depth > 0) {
        if (s[i] == '{') depth++;
        if (s[i] == '}') depth--;
        i++;
      }
    } else {
      out.write(s[i++]);
    }
  }
  return out.toString();
}

void main() {
  test('no English words in Burmese string literals under lib/', () {
    final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'" '|' r'"((?:[^"\\\n]|\\.)*)"');
    final burmese = RegExp(r'[က-႟]');
    final interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
    final word = RegExp(r'[A-Za-z]{2,}');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = _stripInterpolations(lines[i].trimLeft());
        if (line.startsWith('//')) continue;
        for (final m in literal.allMatches(line)) {
          final s = m.group(1) ?? m.group(2)!;
          if (!burmese.hasMatch(s) || _examples.contains(s)) continue;
          final unknown = word
              .allMatches(s.replaceAll(interpolation, ''))
              .map((w) => w.group(0)!)
              .where((w) => !_allowed.contains(w.toLowerCase()));
          if (unknown.isNotEmpty) bad.add('${f.path}:${i + 1}: $s (${unknown.join(', ')})');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
