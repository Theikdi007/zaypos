// BUG-52: Zawgyi detection and conversion (lib/core/text/myanmar_text.dart).
// Fixtures in test/fixtures/zawgyi/ are google/myanmar-tools' own test data
// (Apache 2.0): a Myanmar government news text typed in Zawgyi with its
// Unicode golden, the UDHR in Unicode and in Zawgyi, and the detector's
// compatibility table.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/text/myanmar_text.dart';

List<String> _lines(String name) => File('test/fixtures/zawgyi/$name')
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
    .toList();

void main() {
  group('detector (upstream compatibility table)', () {
    test('every probability in compatibility.tsv is reproduced', () {
      final rows = File('test/fixtures/zawgyi/compatibility.tsv').readAsLinesSync().where((l) => l.isNotEmpty);
      var n = 0;
      for (final row in rows) {
        final tab = row.indexOf('\t');
        final expected = double.parse(row.substring(0, tab));
        final text = row.substring(tab + 1);
        final actual = zawgyiProbability(text);
        if (expected.isInfinite) {
          expect(actual, expected, reason: text);
        } else {
          expect(actual, closeTo(expected, 1e-6), reason: text);
        }
        n++;
      }
      expect(n, greaterThan(40));
    });
  });

  group('normalizeMyanmar', () {
    test('the QA sample: a Zawgyi-typed name becomes Unicode', () {
      const zawgyi = 'ေမာင္ေမာင္'; // ေမာင္ေမာင္
      expect(normalizeMyanmar(zawgyi), 'မောင်မောင်');
    });

    test('real Zawgyi words and phrases', () {
      const cases = {
        'အျပည္ျပည္ဆိုင္ရာ လူ႔အခြင့္အေရး ေၾကညာစာတမ္း': 'အပြည်ပြည်ဆိုင်ရာ လူ့အခွင့်အရေး ကြေညာစာတမ်း',
        'ျမန္မာ': 'မြန်မာ',
        'ေဒၚလွ': 'ဒေါ်လှ',
        'ဦးေက်ာ္ေက်ာ္': 'ဦးကျော်ကျော်',
        'ႏြားႏို႔ ၁ ဗူး': 'နွားနို့ ၁ ဗူး',
        'ရန္ကုန္ၿမိဳ႕': 'ရန်ကုန်မြို့',
        'ေဆး ၁၀ ကဒ္': 'ဆေး ၁၀ ကဒ်',
      };
      cases.forEach((z, u) => expect(normalizeMyanmar(z), u, reason: z));
    });

    test('valid Unicode is never changed, even where the detector alone says Zawgyi', () {
      // Upstream "difficult" cases: Unicode text the model scores ~0.995.
      for (final u in ['ယခု မိုးရွာနေပါသလား။', 'အစားထိုး အထူးအက္ခရာ', 'အသံကို အစားထိုးလိုပါသလား။', 'အခြား', 'နမူနာ', ' ဦး']) {
        expect(normalizeMyanmar(u), same(u), reason: u);
      }
      for (final u in ['မောင်မောင်', 'ဒေါ်လှ', 'သင်္ကြန်', 'စင်္ကာပူ', 'ကုန်စုံဆိုင်', 'ဆေး ၁၀ ကဒ်', 'Coca-Cola 330ml', '09 790 011 152', '']) {
        expect(normalizeMyanmar(u), same(u), reason: u);
      }
    });

    test('Unicode corpora: no line is changed', () {
      final lines = [..._lines('udhr_mya_unicode_src.txt'), ..._lines('mmgov_unicode_out.txt')];
      expect(lines.length, greaterThan(150));
      final changed = [for (final l in lines) if (normalizeMyanmar(l) != l) l];
      expect(changed, isEmpty);
    });

    test('Zawgyi news corpus: every line converts to the Unicode golden', () {
      final z = _lines('mmgov_zawgyi_src.txt');
      final u = _lines('mmgov_unicode_out.txt');
      expect(z.length, u.length);
      final wrong = <String>[];
      for (var i = 0; i < z.length; i++) {
        if (normalizeMyanmar(z[i]) != u[i]) wrong.add('line $i: ${z[i]}');
      }
      expect(wrong, isEmpty);
    });

    test('Zawgyi UDHR: every Myanmar line but one known heading is detected and converted', () {
      final z = _lines('udhr_mya_zawgyi_out.txt');
      final u = _lines('udhr_mya_unicode_src.txt');
      expect(z.length, u.length);
      final missed = <String>[];
      for (var i = 0; i < z.length; i++) {
        if (z[i] == u[i]) continue; // identical in both encodings
        if (normalizeMyanmar(z[i]) == z[i]) missed.add('line $i: ${z[i]}');
      }
      // Known miss: this heading is also well-formed Unicode and the detector
      // gives it only 0.69, so it is left as typed (safe direction: correct
      // Unicode is never altered).
      expect(missed, ['line 14:     အေထြေထြညီလာခံ က']);
    });

    test('Unicode with asat + ု ("ကျွန်ုပ်") and kinzi is not a Zawgyi marker', () {
      for (final u in ['ကျွန်ုပ်', 'သင်္ချိုင်း', 'အင်္ဂလိပ်']) {
        expect(hasZawgyiMarker(u), isFalse, reason: u);
        expect(normalizeMyanmar(u), same(u));
      }
    });
  });
}
