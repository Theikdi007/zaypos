// BUG-59 / BUG-63 (TC-UX-NEW-20): Android's largest font (×2.0) together with the largest display size
// (1080 px at 540 dpi = 320 dp wide, 711 dp tall). No overflow, and no amount, name or label broken
// inside a word: "850 / Ks", "ပစ္စ / ည်း", "Andr / oid", a period tab cut to "ဒီ".
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/product_tile.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// A line may not start here: inside a number / Latin word ("850 / Ks" is fine, "1,50 / 0" and
/// "Andr / oid" are not), or inside a Burmese syllable: on a vowel sign / medial / tone mark, or on a
/// consonant that is the killed final of the syllable before it ("ပစ္စ / ည်း": ည carries ်).
bool _breakInsideWord(String text, int i) {
  if (i <= 0 || i >= text.length) return false;
  bool latin(String c) => RegExp(r'[0-9A-Za-z,.]').hasMatch(c);
  if (latin(text[i - 1]) && latin(text[i])) return true;
  final c = text.codeUnitAt(i);
  if (c >= 0x102B && c <= 0x103E) return true; // dependent vowel signs, asat, medials, virama
  final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : 0;
  return next == 0x103A || next == 0x1039; // asat / virama: this consonant ends the previous syllable
}

/// Every problem on the current screen: overflow errors, one-line texts that were cut, and lines
/// that start inside a word (see [_breakInsideWord]).
List<String> layoutProblems(WidgetTester tester) {
  final out = <String>[
    // Overflow errors with the widgets that hold the overflowing Flex (its "creator" chain).
    for (final d in _errors)
      'error: ${d.exceptionAsString().split('\n').first} @ '
          '${RegExp(r'creator: ([^\n]*)').firstMatch(d.toDiagnosticsNode().toStringDeep(wrapWidth: 100000))?[1]?.split(' ← ').take(22).join(' < ')}',
  ];
  _errors.clear();
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    out.add('exception: $e');
  }
  // A text field's placeholder ("ဥပမာ - …") may be cut with "…" at ×2: the field still works.
  final hints = find.descendant(of: find.byType(InputDecorator), matching: find.byType(RichText)).evaluate().toSet();
  for (final element in find.byType(RichText).evaluate().where((e) => !hints.contains(e))) {
    final p = element.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize || p.size.width <= 0) continue;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty || !p.softWrap) continue; // softWrap: false can't wrap (and may be cut, below)
    if (p.didExceedMaxLines && p.maxLines == 1 && p.overflow != TextOverflow.visible) {
      out.add('cut: "$text"');
      continue;
    }
    final painter = TextPainter(
      text: p.text,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
    )..layout(maxWidth: p.size.width);
    // Where each wrapped line starts.
    final starts = <int>{};
    for (var i = 1; i < text.length; i++) {
      final line = painter.getLineBoundary(TextPosition(offset: i));
      if (line.start == i) starts.add(i);
    }
    final bad = starts.where((i) => _breakInsideWord(text, i)).toList();
    if (bad.isNotEmpty) out.add('broken inside a word: "${_splitAt(text, bad).join(' / ')}"');
    painter.dispose();
  }
  return out;
}

List<String> _splitAt(String text, List<int> cuts) {
  final parts = <String>[];
  var from = 0;
  for (final cut in [...cuts, text.length]) {
    parts.add(text.substring(from, cut));
    from = cut;
  }
  return parts;
}

final _errors = <FlutterErrorDetails>[];

/// Runs [body] with layout errors collected for [layoutProblems] instead of failing at the first one.
Future<void> _collectingErrors(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = _errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = original;
    _errors.clear();
  }
}

void main() {
  setUpAll(loadAppFonts);

  // (screen in dp, text scale): font + display size both max (BUG-59 / BUG-63), font max alone on
  // a default 1080 × 2400 phone (BUG-66), and a normal phone at normal size (nothing may regress).
  for (final (size, scale) in const [(Size(320, 711), 2.0), (Size(411, 914), 2.0), (Size(360, 780), 1.0)]) {
    group('$size × $scale', () => _screens(size, scale));
  }
}

void _screens(Size size, double scale) {
  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = size * 3.375;
    tester.view.devicePixelRatio = 3.375;
    tester.view.padding = const FakeViewPadding(top: 24 * 3.375, bottom: 16 * 3.375);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select('grocery');
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  Future<List<String>> visit(WidgetTester tester, ProviderContainer c, String route) async {
    c.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
    return layoutProblems(tester);
  }

  testWidgets('dashboard (BUG-63 hero row, shop name)', (tester) => _collectingErrors(() async {
        final c = await boot(tester);
        expect(await visit(tester, c, Routes.dashboard), isEmpty);
        // QA's shop "Android…": one long word must not break inside itself.
        final s = c.read(sessionProvider);
        c.read(sessionProvider.notifier).set(ShopSession(tenantId: s.tenantId, shopName: 'Androidshop', startedAt: s.startedAt));
        await tester.pumpAndSettle();
        expect(layoutProblems(tester), isEmpty, reason: 'one-word shop name');
      }));

  testWidgets('reports (BUG-59 period tabs)', (tester) => _collectingErrors(() async {
        final c = await boot(tester);
        layoutProblems(tester); // the dashboard it opens on has its own test
        expect(await visit(tester, c, Routes.reports), isEmpty);
      }));

  testWidgets('POS with an item in the cart, then checkout (BUG-59 cart bar, checkout lines)',
      (tester) => _collectingErrors(() async {
            final c = await boot(tester);
            layoutProblems(tester); // the dashboard it opens on has its own test
            c.read(appRouterProvider).go(Routes.pos);
            await tester.pumpAndSettle();
            await tester.tap(find.text('ပစ္စည်းများ'));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(ProductTile).first);
            await tester.pumpAndSettle();
            expect(layoutProblems(tester), isEmpty, reason: 'POS');
            expect(await visit(tester, c, Routes.checkout), isEmpty, reason: 'checkout');
          }));

  testWidgets('add customer (BUG-59 cancel button)', (tester) => _collectingErrors(() async {
        final c = await boot(tester);
        layoutProblems(tester); // the dashboard it opens on has its own test
        expect(await visit(tester, c, Routes.addCustomer), isEmpty);
      }));
}
