// QA round 16 (targeted re-test of the round-15 fixes, fix/android @ 3c9e102).
//   TC-PROD-NEW-37  a cost the owner TYPES as 0 (a service with no material cost) is a known cost, not "အရင်းမသိ"
//   TC-UX-NEW-23    expiry picker, keyboard-entry mode: a date typed with the phone's (Latin) digits is accepted
//   TC-DEBT-NEW-15  Zawgyi detection: realistic Zawgyi shop text is converted; ambiguous no-marker text is reported
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/text/myanmar_text.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import 'qa_form_helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

  // ------------------------------------------------------------------------------------------------ TC-PROD-NEW-37
  testWidgets('TC-PROD-NEW-37 service template: a service saved with cost typed as "0" and price 5,000, sold once → '
      'the dashboard profit is 5,000 Ks (a typed 0 is a known cost), not "အရင်းမသိ"', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [...fakeRepositoryOverrides, initialLimitsProvider.overrideWithValue(bundledLimits())],
    );
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select('service');
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    await tester.enterText(keyed('productName'), 'QA r16 ဆံပင်ညှပ်');
    await tester.enterText(keyed('price'), '5000');
    await tester.enterText(keyed('cost'), '0'); // the owner says: this service costs me nothing
    await tester.pumpAndSettle();
    final formSaysUnknown = find.byKey(const ValueKey('costUnknown')).evaluate().isNotEmpty;
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    final p = c.read(fakeDatabaseProvider).products.firstWhere((x) => x.name == 'QA r16 ဆံပင်ညှပ်');

    // The fake shop is seeded with today's sales (all with costs): compare the dashboard before and after.
    List<String> texts() => [
          for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
        ];
    int profit(List<String> t) => int.parse(t[t.indexOf('အမြတ်') + 1].replaceAll(RegExp(r'[^0-9]'), ''));
    c.read(appRouterProvider).go(Routes.dashboard);
    await tester.pumpAndSettle();
    final before = texts();
    expect(before.where((t) => t.contains('အရင်းမသိ')), isEmpty, reason: 'precondition: no unknown cost before; $before');
    await tester.runAsync(() => sell(c, [draft(productId: p.id, name: p.name, price: p.price, cost: p.cost)]));
    await tester.pumpAndSettle();
    final after = texts();
    expect(after.where((t) => t.contains('အရင်းမသိ')), isEmpty,
        reason: 'the owner typed cost 0 (saved cost=${p.cost}; the form already showed "အရင်းမသိ": $formSaysUnknown). '
            'Dashboard after the sale: $after');
    expect(profit(after), profit(before) + 5000, reason: 'the 5,000 Ks service is all profit');
  });


  // ------------------------------------------------------------------------------------------------ TC-UX-NEW-23
  for (final typed in ['28/11/2030', '၂၈/၁၁/၂၀၃၀']) {
    testWidgets('TC-UX-NEW-23 pharmacy Add Product → "သက်တမ်းကုန်ရက်" → pencil (keyboard entry) → type "$typed" → '
        'ရွေးမယ် → the expiry is 28 Nov 2030', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [...fakeRepositoryOverrides, initialLimitsProvider.overrideWithValue(bundledLimits())],
      );
      addTearDown(c.dispose);
      c.read(shopTemplateProvider.notifier).select('pharmacy');
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await pickExpiryWarn(tester, warn30Label);
      final f = find.bySemanticsLabel('သက်တမ်းကုန်ရက်');
      await tester.ensureVisible(f.last);
      await tester.pumpAndSettle();
      await tester.tap(f.last);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      final input = find.descendant(of: find.byType(Dialog), matching: find.byType(EditableText));
      final prefilled = tester.widget<EditableText>(input).controller.text;
      await tester.enterText(input, typed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ရွေးမယ်'));
      await tester.pumpAndSettle();
      final dialogTexts = [
        for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Dialog), matching: find.byType(Text))))
          t.data ?? '',
      ];
      expect(find.byType(Dialog), findsNothing,
          reason: 'the picker should accept "$typed" (pre-filled text was "$prefilled"); still open with: $dialogTexts');
      expect(find.textContaining('2030'), findsWidgets, reason: 'the form shows the typed expiry');
    });
  }

  // ------------------------------------------------------------------------------------------------ TC-DEBT-NEW-15
  // Realistic Zawgyi shop words / names (as a Zawgyi keyboard commits them) → the Unicode QA expects.
  const converts = <(String, String)>[
    ('ေမာင္ေမာင္', 'မောင်မောင်'),
    ('ေက်ာ္ေက်ာ္', 'ကျော်ကျော်'),
    ('ရန္ကုန္', 'ရန်ကုန်'),
    ('ေဆးလံုး', 'ဆေးလုံး'),
    ('ၾကက္ဥ', 'ကြက်ဥ'),
    ('သၾကား', 'သကြား'),
    ('ဆန္', 'ဆန်'),
    ('ေရ', 'ရေ'),
    ('ေၾကြးက်န္', 'ကြွေးကျန်'),
    ('ဦးေအာင္', 'ဦးအောင်'),
  ];
  for (final (zg, uni) in converts) {
    test('TC-DEBT-NEW-15 Zawgyi "$zg" is stored as Unicode "$uni"', () {
      expect(normalizeMyanmar(zg).runes.toList(), uni.runes.toList(),
          reason: 'zawgyiProbability=${zawgyiProbability(zg)} marker=${hasZawgyiMarker(zg)}');
    });
  }
  const keeps = ['ယခု မိုးရွာနေပါသလား', 'ကျွန်ုပ်', 'မောင်မောင်', 'ဒေါ်လှ', 'ကြက်ဥ', 'ဆေးလုံး', 'ရန်ကုန်မြို့', 'သကြား', 'ကလေး'];
  for (final u in keeps) {
    test('TC-DEBT-NEW-15 valid Unicode "$u" is not changed', () {
      expect(normalizeMyanmar(u), u, reason: 'zawgyiProbability=${zawgyiProbability(u)}');
    });
  }
}
