import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// Forms check the server's rules (bundled /sync/limits) before saving, and
/// store values the way the server will (§1.5, §7).
void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, String route, {String template = 'grocery'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    c.read(shopTemplateProvider.notifier).select(template);
    c.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
    return c;
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
  }

  testWidgets('add product: a name over 150 characters is refused with the server limit; nothing saved', (tester) async {
    final c = await boot(tester, '/products/new');
    final before = c.read(fakeDatabaseProvider).products.length;

    await tester.enterText(field('productName'), 'က' * 151);
    await save(tester);

    expect(find.text('ပစ္စည်းအမည် စာလုံး ၁၅၀ လုံးထက် မပိုရပါ။'), findsOneWidget);
    expect(c.read(fakeDatabaseProvider).products.length, before);
  });

  testWidgets('add product: barcode letters are refused; Myanmar digits are stored as 0-9', (tester) async {
    final c = await boot(tester, '/products/new');
    await tester.enterText(field('productName'), 'ဆပ်ပြာ');
    await tester.enterText(field('barcode'), '885ကခ');
    await save(tester);
    expect(find.text('Barcode မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။'), findsOneWidget);

    await tester.enterText(field('barcode'), '၈၈၅၀၉၉၉၃၂၀၀၁၄');
    await save(tester);
    final saved = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.name == 'ဆပ်ပြာ');
    expect(saved.barcode, '8850999320014');
    expect(saved.category, isNotEmpty, reason: 'the server requires a category');
  });

  testWidgets('add product (template without categories): a default category is used', (tester) async {
    final c = await boot(tester, '/products/new', template: 'other');
    await tester.enterText(field('productName'), 'ပစ္စည်း');
    await tester.enterText(field('price'), '1500');
    await save(tester);
    final saved = c.read(fakeDatabaseProvider).products.firstWhere((p) => p.name == 'ပစ္စည်း', orElse: () => throw 'not saved');
    expect(saved.category, isNotEmpty);
  });

  testWidgets('add product (phone): an IMEI with letters is refused; duplicates too', (tester) async {
    await boot(tester, '/products/new', template: 'phone');
    final imei = field('imei');
    await tester.ensureVisible(imei);
    await tester.enterText(imei, '35693803564380X');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('IMEI / Serial မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။'), findsNothing,
        reason: 'latin letters are ASCII: allowed');

    await tester.enterText(imei, '၃၅၆၉၃၈၀၃၅၆၄၃၈၀၉');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('356938035643809'), findsOneWidget, reason: 'stored as ASCII digits');

    await tester.enterText(imei, '356938035643809');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('ဒီ IMEI ထည့်ပြီးသားပါ။'), findsOneWidget);

    await tester.enterText(imei, 'IMEI ကခ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('IMEI / Serial မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။'), findsOneWidget);
  });

  testWidgets('add customer: name limit; phone stored the way the server stores it', (tester) async {
    final c = await boot(tester, '/customers/new');
    final inputs = find.byType(EditableText);
    await tester.enterText(inputs.at(0), 'က' * 101);
    await save(tester);
    expect(find.text('အမည် စာလုံး ၁၀၀ လုံးထက် မပိုရပါ။'), findsOneWidget);

    await tester.enterText(inputs.at(0), 'မမြင့်မြင့်');
    await tester.enterText(inputs.at(1), '၀၉ ၇၇၇ ၁၂၃ ၄၅၆');
    await save(tester);
    final saved = c.read(fakeDatabaseProvider).customers.singleWhere((x) => x.name == 'မမြင့်မြင့်');
    expect(saved.phone, '09 777 123 456');
  });
}
