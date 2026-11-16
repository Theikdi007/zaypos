import 'dart:convert';
import 'dart:typed_data';

import 'zawgyi/model_data.dart';
import 'zawgyi/transliterate_z2u.dart';
import 'zawgyi/zawgyi_unicode_markov_model.dart';

/// Zawgyi → Unicode for free text (BUG-52).
///
/// Many older Myanmar Android phones still type with a Zawgyi keyboard. Zawgyi
/// re-uses the Myanmar Unicode block with a different meaning and order, so the
/// text is stored "as is", draws broken with a Unicode font and is not found by
/// a Unicode search. Every free-text field is passed through [normalizeMyanmar]
/// before it is saved; the server does the same on incoming text
/// (backend `MyanmarText.NormalizeToUnicode`, the SAME rule).
///
/// The rule (kept identical on both sides):
/// convert only if Google myanmar-tools' detector gives a Zawgyi probability
/// ≥ [zawgyiThreshold] AND the text contains at least one sequence that is
/// impossible in well-formed Unicode Burmese ([hasZawgyiMarker]). The detector
/// alone scores some valid Unicode text at 0.995 (e.g. "ယခု မိုးရွာနေပါသလား။"),
/// so the marker check is what keeps correct Unicode from being "converted".
String normalizeMyanmar(String text) {
  if (!_hasMyanmar(text)) return text;
  if (!hasZawgyiMarker(text)) return text;
  if (zawgyiProbability(text) < zawgyiThreshold) return text;
  return _z2u.convert(text);
}

/// See [normalizeMyanmar].
const zawgyiThreshold = 0.5;

/// Probability (0..1) that [text] is Zawgyi; -∞ when it has no Myanmar code points.
double zawgyiProbability(String text) => _model.predict(text);

/// True if [text] has a sequence that well-formed Unicode Burmese never has:
/// 1. a Zawgyi-only code point (U+105A, U+1060–U+1097);
/// 2. a dependent sign (U+102B–U+103E) at the start or right after a
///    non-Myanmar character (Zawgyi types "ေ" / "ျ" before the consonant);
/// 3. U+1039 not followed by a consonant (Zawgyi uses U+1039 as asat);
/// 4. U+103A followed by a vowel sign or medial (Zawgyi uses U+103A as the
///    medial ya; Unicode asat is never followed by those, except U+102F/U+1030
///    as in "ကျွန်ုပ်", which are therefore not counted).
bool hasZawgyiMarker(String text) {
  final cps = text.runes.toList(growable: false);
  for (var i = 0; i < cps.length; i++) {
    final c = cps[i];
    if (c == 0x105A || (c >= 0x1060 && c <= 0x1097)) return true;
    if (c >= 0x102B && c <= 0x103E) {
      final prev = i == 0 ? -1 : cps[i - 1];
      if (prev < 0x1000 || prev > 0x109F) return true;
    }
    if (c == 0x1039) {
      final next = i + 1 < cps.length ? cps[i + 1] : -1;
      if (next < 0x1000 || next > 0x1021) return true;
    }
    if (c == 0x103A && i + 1 < cps.length) {
      final next = cps[i + 1];
      if ((next >= 0x102B && next <= 0x102E) || next == 0x1032 || (next >= 0x103B && next <= 0x103E)) {
        return true;
      }
    }
  }
  return false;
}

/// [normalizeMyanmar] for nullable fields.
String? normalizeMyanmarOrNull(String? text) =>
    text == null ? null : normalizeMyanmar(text);

bool _hasMyanmar(String s) {
  for (final u in s.codeUnits) {
    if ((u >= 0x1000 && u <= 0x109F) || (u >= 0xA9E0 && u <= 0xA9FF) || (u >= 0xAA60 && u <= 0xAA7F)) {
      return true;
    }
  }
  return false;
}

final _model = ZawGyiUnicodeMarkovModel(
  ByteData.sublistView(Uint8List.fromList(base64Decode(zawgyiModelBase64))),
);
final _z2u = TransliterateZ2U('Z2U');
