// QA round 15 (Android round, fix/android @ 32c7af1). Widget tests for the findings an in-memory test can prove; the
// emulator evidence is in docs/qa/evidence/round-15/ (see round-15-summary.md).
//   TC-AUTH-NEW-4  system BACK on register step 2 goes to step 1 like the screen's own back arrow (BUG-51)
//   TC-DEBT-NEW-14 a customer name typed with a Zawgyi keyboard is found by its Unicode spelling (BUG-52)
//   TC-PROD-NEW-36 Add Product does not save a cost the owner never typed (BUG-53)
//   TC-UX-NEW-16   the expiry date picker has no English (TC-UX-02 rule) (BUG-54)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart' hide CustomerRow;
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/core/widgets/common.dart' show AppInput;
import 'package:zaypos_app/features/customers/presentation/widgets/customer_row.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_auth_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import 'qa_form_helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> bootShop(WidgetTester tester, {String? template}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides,
        initialLimitsProvider.overrideWithValue(bundledLimits()),
        otpEnabledProvider.overrideWithValue(true), // TC-AUTH-NEW-4 is the SMS OTP register wizard
      ],
    );
    addTearDown(c.dispose);
    if (template != null) c.read(shopTemplateProvider.notifier).select(template);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

  // ------------------------------------------------------------------------------------------------ TC-AUTH-NEW-4
  group('TC-AUTH-NEW-4', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    for (final useArrow in [true, false]) {
      testWidgets(
        useArrow
            ? 'TC-AUTH-NEW-4 control: the screen\'s "နောက်သို့" arrow on register step 2 goes to step 1'
            : 'TC-AUTH-NEW-4 register step 2: Android system BACK goes to step 1 (like the "နောက်သို့" arrow), the '
                  'verified phone and code kept; it does not drop the wizard to Login',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final c = ProviderContainer(
            overrides: [
              ...fakeOverrides(boot: BootState(deviceId: newId())),
              appDatabaseProvider.overrideWithValue(db),
              secureStoreProvider.overrideWithValue(MemorySecureStore()),
              authApiProvider.overrideWithValue(FakeAuthApi()),
              otpEnabledProvider.overrideWithValue(true),
              pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
            ],
          );
          addTearDown(c.dispose);
          await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
          await tester.pumpAndSettle();

          await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(EditableText).first, '9 7123 4567');
          await tester.tap(find.text('ကုဒ်ပို့မယ်'));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          await tester.enterText(find.byType(EditableText).last, '123456');
          await tester.pump();
          await tester.tap(find.text('ဆက်သွားမယ်'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('အဆင့် 2 / 4'), findsOneWidget, reason: 'precondition: on step 2');

          if (useArrow) {
            await tester.tap(find.bySemanticsLabel('နောက်သို့').first);
          } else {
            // What Android's back key / back gesture does: the engine sends popRoute.
            await tester.binding.handlePopRoute();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('ဝင်မယ်'), findsNothing, reason: 'back must not throw the half-done registration away (Login shown)');
          expect(find.text('အဆင့် 1 / 4'), findsOneWidget, reason: 'same as the screen\'s own back arrow (_back: step--)');
        },
      );
    }
  });

  // ------------------------------------------------------------------------------------------------ TC-DEBT-NEW-14
  // Round 16: strengthened. The round-15 version created the customer through the service, tapped "အားလုံး" while it
  // was off-screen in the scrolling chip row (the tap missed: "would not hit test") and counted texts minus 1 for the
  // search box. Now: the name is typed into the real Add Customer form, the stored code points are checked, the chip
  // is scrolled into view, and only real CustomerRow widgets are counted, for a Unicode AND a Zawgyi search.
  testWidgets('TC-DEBT-NEW-14 a customer saved with a Zawgyi-typed name ("ေမာင္ေမာင္") is stored as Unicode '
      '"မောင်မောင်" and found by the Unicode and by the Zawgyi spelling', (tester) async {
    final c = await bootShop(tester);
    const zawgyi = 'ေမာင္ေမာင္'; // U+1031 U+1019 U+102C U+1004 U+1039 x2
    const unicode = 'မောင်မောင်'; // U+1019 U+1031 U+102C U+1004 U+103A x2
    c.read(appRouterProvider).push(Routes.addCustomer);
    await tester.pumpAndSettle();
    Finder input(String label) => find.descendant(
        of: find.byWidgetPredicate((w) => w is AppInput && w.semanticLabel == label), matching: find.byType(EditableText));
    await tester.enterText(input('အမည်'), zawgyi);
    await tester.enterText(input('ဖုန်းနံပါတ်'), '09 790 011 152');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    final saved = c.read(fakeDatabaseProvider).customers.where((x) => x.phone.replaceAll(' ', '').endsWith('790011152'));
    expect(saved, hasLength(1), reason: 'saved through the Add Customer form');
    expect(saved.single.name.runes.toList(), unicode.runes.toList(), reason: 'stored in Unicode (code points)');

    c.read(appRouterProvider).go(Routes.customers);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('အားလုံး').first); // the chip row scrolls sideways
    await tester.pumpAndSettle();
    await tester.tap(find.text('အားလုံး').first);
    await tester.pumpAndSettle();
    final allRows = find.byType(CustomerRow).evaluate().length;
    expect(find.descendant(of: find.byType(CustomerRow), matching: find.text(unicode)), findsOneWidget,
        reason: 'the "အားလုံး" tab lists the customer under its Unicode name ($allRows rows)');
    for (final query in [unicode, zawgyi, 'မောင်', 'ေမာင္']) {
      await tester.enterText(find.byType(EditableText).first, query);
      await tester.pumpAndSettle();
      expect(find.byType(CustomerRow), findsOneWidget, reason: 'search "$query" finds exactly the one customer');
      expect(find.descendant(of: find.byType(CustomerRow), matching: find.text(unicode)), findsOneWidget,
          reason: 'search "$query": the row shows the Unicode name');
    }
  });

  // ------------------------------------------------------------------------------------------------ TC-PROD-NEW-36
  testWidgets('TC-PROD-NEW-36 Add Product (grocery): only name and price typed → the saved cost is not the template\'s '
      'sample cost (450)', (tester) async {
    final c = await bootShop(tester, template: 'grocery');
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    final costShown = tester.widgetList<EditableText>(find.byType(EditableText)).map((e) => e.controller.text).toList();
    await tester.enterText(keyed('productName'), 'QA r15 cost check');
    await tester.enterText(keyed('price'), '1000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    final p = c.read(fakeDatabaseProvider).products.where((x) => x.name == 'QA r15 cost check').firstOrNull;
    expect(p, isNotNull, reason: 'saved');
    expect(
      p!.cost,
      isNot(450),
      reason:
          'the form opened with these field texts $costShown; a cost the owner never typed must not be saved as real '
          'cost (profit on the dashboard and reports = price − this cost)',
    );
  });

  // ------------------------------------------------------------------------------------------------ TC-UX-NEW-16
  testWidgets('TC-UX-NEW-16 pharmacy Add Product → ရက် ၃၀ → "သက်တမ်းကုန်ရက်": the date picker shows no English '
      '("Select date", "Cancel", "OK", month names)', (tester) async {
    await bootShop(tester, template: 'pharmacy');
    final c = ProviderScope.containerOf(tester.element(find.byType(ZayPosApp)));
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    await pickExpiryWarn(tester, warn30Label);
    final f = find.bySemanticsLabel('သက်တမ်းကုန်ရက်');
    await tester.ensureVisible(f.last);
    await tester.pumpAndSettle();
    await tester.tap(f.last);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'precondition: the picker is open');
    final english = [
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Dialog), matching: find.byType(Text))))
        if ((t.data ?? t.textSpan?.toPlainText() ?? '').contains(RegExp('[A-Za-z]{2,}'))) t.data ?? t.textSpan!.toPlainText(),
    ];
    expect(english, isEmpty, reason: 'TC-UX-02: no English on Burmese screens except brand / payment names');
  });
}
