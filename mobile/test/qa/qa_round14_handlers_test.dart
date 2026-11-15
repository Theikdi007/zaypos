// QA round 14 — TC-UX-NEW-12 (new): review of the developer's guard m/no_dead_handlers_test.dart (BUG-46).
// The guard only looks at a fixed list of Flutter names (onPressed, onTap, onLongPress, …). The app's own widgets take tap
// callbacks under other names (ScreenHeader `onBack` ×13, keypad `onKey` ×7, `onPick`, `onScan`, `onEdit`, `onRestock`,
// `onResend`, `onReverse`, Switch / SegmentedTabs `onChanged` …), so `onBack: () {}` or `onScan: () {}` would pass it.
// It also misses an empty method passed by name (`onTap: _noop`) and a handler that only logs.
// This scan covers every `on<Name>:` callback in lib/ (minus the stream `onError` swallow in sync_lifecycle.dart, which is
// not a control), empty tear-offs, and log-only bodies. It does not replace the simulator sweep (r14_sweep_test.dart): no
// static scan can see a control that looks tappable but has no handler at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../no_dead_handlers_test.dart' show findDeadHandlers;

final _anyCallback = RegExp(
  r'\b(on[A-Z]\w*)\s*:\s*\([^)]*\)\s*(?:async\s*)?'
  r'(?:\{(?:\s|//[^\n]*\n|/\*(?:[^*]|\*(?!/))*\*/|(?:debugPrint|print)\([^;]*\);|return;)*\}'
  r'|=>\s*(?:null|\{\s*\}|(?:debugPrint|print)\([^)]*\)))',
);
final _emptyMethod = RegExp(r'\b(?:void|Future<void>)\s+(_?\w+)\s*\([^)]*\)\s*(?:async\s*)?\{\s*\}');

List<String> qaScan(String source, String path) {
  final hits = <String>[];
  for (final m in _anyCallback.allMatches(source)) {
    if (m[1] == 'onError') continue; // Stream.listen(onError: …): not a control
    final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
    hits.add('$path:$line  ${m[0]!.replaceAll(RegExp(r'\s+'), ' ')}');
  }
  for (final m in _emptyMethod.allMatches(source)) {
    final name = m[1]!;
    for (final use in RegExp('\\bon[A-Z]\\w*\\s*:\\s*${RegExp.escape(name)}\\b(?!\\()').allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, use.start)).length + 1;
      hits.add('$path:$line  ${use[0]} (empty method $name)');
    }
  }
  return hits;
}

void main() {
  test('TC-UX-NEW-12 review: what the developer guard does NOT catch (documented, not a failure)', () {
    const missed = [
      'ScreenHeader(onBack: () {})',
      'Keypad(onKey: (_) {})',
      'Switch(value: v, onChanged: (_) {})',
      'Sheet(onScan: () async {})',
      'void _noop() {}\nInkWell(onTap: _noop)',
      "TextButton(onPressed: () => debugPrint('later'))",
      'IconButton(onPressed: () { return; })',
    ];
    final notCaught = [for (final s in missed) if (findDeadHandlers(s, 'x.dart').isEmpty) s];
    // ignore: avoid_print
    print('TC-UX-NEW-12 developer guard misses ${notCaught.length}/${missed.length}: ${notCaught.join(' | ')}');
    for (final s in missed) {
      expect(qaScan(s, 'x.dart'), isNotEmpty, reason: 'QA scan must catch: $s');
    }
    expect(qaScan('onPressed: () => context.pop(),\nonTap: () { setState(() => x++); }\nonPressed: null,', 'x.dart'),
        isEmpty);
  });

  test('TC-UX-NEW-12 no callback of ANY name in lib/ is empty, log-only or an empty method', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();
    expect(files.length, greaterThan(50));
    final hits = [for (final f in files) ...qaScan(f.readAsStringSync(), f.path)];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
