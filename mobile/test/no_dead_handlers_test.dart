// BUG-46: no button in the app may look ready and do nothing. This scans every
// Dart file under lib/ for a tap/press handler that is empty or only a TODO,
// e.g. `onPressed: () {}`, `onTap: () async {}`, `onPressed: () => null`,
// `onTap: () { // TODO }`. A control that is not ready yet is hidden, or given
// `onPressed: null` (shown disabled), never an empty handler.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Handler names that make a widget tappable.
const _handlers = r'on(?:Pressed|Tap|TapDown|TapUp|LongPress|DoubleTap|SecondaryTap|Selected|Submitted)';

/// `() {}`, `(_) async {}`, `() { // TODO … }`, `() { /* … */ }`, `() => null`, `() => {}`.
final deadHandler = RegExp(
  '\\b$_handlers\\s*:\\s*\\([^)]*\\)\\s*(?:async\\s*)?'
  r'(?:\{(?:\s|//[^\n]*\n|/\*(?:[^*]|\*(?!/))*\*/)*\}|=>\s*(?:null|\{\s*\}))',
);

/// A handler whose first statement is a TODO comment, even if code follows.
final todoHandler = RegExp('\\b$_handlers\\s*:\\s*\\([^)]*\\)\\s*(?:async\\s*)?\\{\\s*//\\s*TODO', caseSensitive: false);

List<String> findDeadHandlers(String source, String path) {
  final hits = <String>[];
  for (final re in [deadHandler, todoHandler]) {
    for (final m in re.allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
      final text = m[0]!.replaceAll(RegExp(r'\s+'), ' ');
      final hit = '$path:$line  $text';
      if (!hits.contains(hit)) hits.add(hit);
    }
  }
  return hits;
}

void main() {
  group('the scanner itself', () {
    test('finds empty and TODO handlers', () {
      const bad = [
        'onPressed: () {},',
        'onTap: () {}',
        'onTap: (){ }',
        'onPressed: () async {},',
        'onLongPress: () => null,',
        'onPressed: () => {},',
        'onTap: () {\n  // TODO: open contacts\n},',
        'onTap: () { /* later */ },',
        'onSelected: (_) {},',
        'onPressed: () {\n  // todo later\n  debugPrint("x");\n},',
      ];
      for (final s in bad) {
        expect(findDeadHandlers(s, 'x.dart'), isNotEmpty, reason: s);
      }
    });

    test('leaves real handlers and disabled buttons alone', () {
      const good = [
        'onPressed: null,',
        'onPressed: () => context.pop(),',
        'onTap: () { setState(() {}); },',
        'onPressed: () async { await save(); },',
        'onTap: onReverse,',
        'onChanged: (_) {},', // a field callback, not a tap target
        'final f = () {};',
      ];
      for (final s in good) {
        expect(findDeadHandlers(s, 'x.dart'), isEmpty, reason: s);
      }
    });
  });

  test('BUG-46: no tappable widget in lib/ has an empty or TODO handler', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from mobile/');
    final files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();
    expect(files.length, greaterThan(50), reason: 'the scan must actually see the app code');
    final hits = [for (final f in files) ...findDeadHandlers(f.readAsStringSync(), f.path)];
    expect(hits, isEmpty, reason: 'Buttons that do nothing. Hide them or pass null (disabled):\n${hits.join('\n')}');
  });
}
