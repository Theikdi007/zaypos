// Vendored from google/myanmar-tools clients/dart (commit 13b4af6aaac63849fa122374f93bc77a42674027).
// Apache License 2.0, see LICENSE in this folder. Local changes: imports, lints, null-safe group substitution.
// ignore_for_file: prefer_interpolation_to_compose_strings, unnecessary_this, prefer_final_fields, use_super_parameters

import 'phase.dart';

/// A engine for running the phases of transliteration, similar to the ICU4J transliterator.
abstract class Transliterate {
  final String name; // For identification
  late List<Phase> _transliteratePhases;

  Transliterate(this.name) {
    _transliteratePhases = [];
  }
  Phase addPhase() {
    Phase newPhase = Phase();
    newPhase.setInfo(' ${_transliteratePhases.length}');
    _transliteratePhases.add(newPhase);
    return newPhase;
  }

  String convert(String inString) {
    return _runAllPhases(inString);
  }

  String _runAllPhases(String inString) {
    String outString = inString;

    for (final phase in _transliteratePhases) {
      outString = phase.runPhase(outString);
    }
    return outString;
  }
}
