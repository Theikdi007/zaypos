// QA round 1 — section 12 (UX): TC-UX-02 and TC-UX-04.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

/// Routes of the signed-in app (fake repositories with the design's sample data).
final _appRoutes = <String Function()>[
  () => '/',
  () => '/sales',
  () => '/sales/${SeedIds.sale1030}',
  () => '/sales/${SeedIds.sale1027}',
  () => '/sales/${SeedIds.sale1032}/receipt',
  () => '/reports',
  () => '/pos',
  () => '/checkout',
  () => '/products',
  () => '/products?filter=low',
  () => '/products/new',
  () => '/customers',
  () => '/customers/new',
  () => '/customers/${SeedIds.aungKyaw}',
  () => '/settings/features',
  () => '/settings/sync-review',
  () => '/register?step=2',
  () => '/register?step=3',
];

/// Routes reachable signed out.
const _publicRoutes = ['/login', '/register', '/register?step=2', '/register?step=3', '/register?step=4', '/pin-reset'];

/// Latin words allowed on Burmese screens: brand / payment names and loanwords
/// that the design itself uses (they appear in docs/qa/test-cases.md expected texts).
const _allowedLatin = {
  'zaypos', 'kbzpay', 'wavepay', 'kbz', 'wave', 'viber', 'ks', 'pin', 'otp', 'sms', 'imei', 'barcode', 'scan', 'stock',
  'sync', 'quick', 'sale', 'batch', 'excel', 'support', 'demo', 'screenshot', 'features', 'feature', 'template', 'variant',
  'serial', 'offline', 'app', 'server', 'pro', 'free', 'ml', 'l', 'kg', 'id',
  'xx', 'xxx', // phone number placeholders (09 7xx xxx 102)
};

/// Visible strings with Latin words outside the allow-list, or broken Unicode.
List<String> _badStrings(WidgetTester tester) {
  final bad = <String>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.contains('�')) bad.add('broken unicode: $s');
    // A Myanmar combining mark cannot start a string (sign of broken / Zawgyi text).
    if (RegExp(r'^[ါ-ှ]').hasMatch(s)) bad.add('starts with a combining mark: $s');
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(s).map((m) => m.group(0)!.toLowerCase());
    final unknown = words.where((w) => !_allowedLatin.contains(w)).toList();
    if (unknown.isNotEmpty) bad.add('"$s" (English: ${unknown.join(', ')})');
  }
  return bad;
}

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, {required Size size, BootState? state}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeOverrides(boot: state));
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  // ---------------------------------------------------------------- TC-UX-04
  group('TC-UX-04 every screen at 320 px width: no RenderFlex overflow', () {
    const small = Size(320, 568); // iPhone SE (1st gen) / small Android
    for (final r in _appRoutes) {
      testWidgets('signed in ${r()}', (tester) async {
        final c = await boot(tester, size: small);
        // A cart with a long product name, a quick sale and a 2-digit quantity (checkout / POS bar).
        c.read(cartProvider.notifier)
          ..addQuick(125000, 'ဆပ်ပြာ အကြီး (၁၂ လုံးတွဲ) ပါကင်')
          ..addQuick(2500, '');
        c.read(appRouterProvider).go(r());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: r());
      });
    }
    for (final r in _publicRoutes) {
      testWidgets('signed out $r', (tester) async {
        final c = await boot(tester, size: small, state: BootState(deviceId: newId()));
        c.read(appRouterProvider).go(r);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: r);
      });
    }
    for (final t in ['pharmacy', 'phone', 'fashion', 'hardware']) {
      testWidgets('add product, $t template, scrolled to the end', (tester) async {
        final c = await boot(tester, size: small);
        c.read(shopTemplateProvider.notifier).select(t);
        c.read(appRouterProvider).go('/products/new');
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------- TC-UX-02
  testWidgets('TC-UX-02 no English left on Burmese screens (except brand/payment names) and no broken Unicode',
      (tester) async {
    final found = <String, List<String>>{};
    final c = await boot(tester, size: const Size(390, 844));
    for (final r in _appRoutes) {
      c.read(appRouterProvider).go(r());
      await tester.pumpAndSettle();
      final bad = _badStrings(tester);
      if (bad.isNotEmpty) found[r()] = bad;
    }
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.toSet().join('\n  ')}').join('\n'));
  });

  testWidgets('TC-UX-02 signed-out screens', (tester) async {
    final found = <String, List<String>>{};
    final c = await boot(tester, size: const Size(390, 844), state: BootState(deviceId: newId()));
    for (final r in _publicRoutes) {
      c.read(appRouterProvider).go(r);
      await tester.pumpAndSettle();
      final bad = _badStrings(tester);
      if (bad.isNotEmpty) found[r] = bad;
    }
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.toSet().join('\n  ')}').join('\n'));
  });
}
