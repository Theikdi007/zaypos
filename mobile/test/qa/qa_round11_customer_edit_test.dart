// QA round 11 — ae22869 (BUG-33), adversarial, through the real screens (fake repositories, bundled form rules).
//
// Owner: "make 'ပြင်ဆင်မယ်' open the existing add-customer form in edit mode (name, phone, address, credit limit). Same
// validation as add (duplicate phone warning). Changes sync like other edits. Lowering a limit below the current balance
// is allowed; just show the balance next to the field." Developer: the Add form had no duplicate-phone warning before;
// one was added to both add and edit (warn, don't block; only when the number is new / changed). The button keeps the
// semantic label 'ပြင်ဆင်ရန်'.
//
// What the developer's m/customer_edit_test.dart does not do, and this file does: the go_router claim behind the edit of
// qa_round10_customer_edit_test.dart (context.push does not change currentConfiguration.uri); a lowered limit is used
// by the credit-limit warning at sale time (POS → checkout → အကြွေး); the seeded customers' placeholder phones
// ("09 7xx xxx 102"); the same number typed with spaces; and no English on the edit form.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import 'qa_round9_sync_text_test.dart' show badStrings;

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
  Customer stored(ProviderContainer c, String id) => db(c).customers.singleWhere((x) => x.id == id);
  // By the AppInput's Semantics widget (an EMPTY field's semantics node also carries its hint, so bySemanticsLabel misses it).
  Finder field(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), matching: find.byType(EditableText));

  Future<void> openEdit(WidgetTester tester, ProviderContainer c, String id) async {
    c.read(appRouterProvider).go(Routes.customer(id));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
  }

  const dupTitle = 'ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ';

  // ================================================================ review of the developer's edit (go_router claim)
  testWidgets('TC-DEBT-NEW-6 review: "ပြင်ဆင်ရန်" pushes /customers/<id>/edit on top of the debt screen; '
      'routerDelegate.currentConfiguration.uri does not change on a push (developer\'s claim)', (tester) async {
    final c = await boot(tester);
    final router = c.read(appRouterProvider);
    router.go(Routes.customer(SeedIds.khinMa));
    await tester.pumpAndSettle();
    final before = router.routerDelegate.currentConfiguration.uri.toString();
    await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
    await tester.pumpAndSettle();
    final cfg = router.routerDelegate.currentConfiguration;
    final last = cfg.matches.last;
    final top = last is ImperativeRouteMatch ? last.matches.uri.toString() : cfg.uri.toString();
    // ignore: avoid_print
    print('TC-DEBT-NEW-6 review: uri before=$before after=${cfg.uri} top=$top (${last.runtimeType})');
    expect(cfg.uri.toString(), before, reason: 'the claim: a push leaves currentConfiguration.uri as it was');
    expect(top, Routes.editCustomer(SeedIds.khinMa), reason: 'the pushed edit route is on top');
    expect(find.text('ဖောက်သည် ပြင်ဆင်ရန်'), findsOneWidget);
    // back (the "ပိတ်ရန်" close button) returns to the debt screen
    await tester.tap(find.bySemanticsLabel('ပိတ်ရန်').first);
    await tester.pumpAndSettle();
    expect(find.text('အကြွေးစာရင်း'), findsOneWidget);
  });

  // ================================================================ TC-DEBT-NEW-7 lowered limit → sale-time warning
  testWidgets('TC-DEBT-NEW-7 edit ဦးသန်းထွန်း (owes 96,000): the balance is shown next to the limit; a limit of 50,000 '
      '(below the balance) is saved; at checkout on credit the warning shows the NEW limit; clearing it removes the '
      'warning', (tester) async {
    final c = await boot(tester);
    await openEdit(tester, c, SeedIds.thanHtun);
    expect(find.descendant(of: find.byKey(const ValueKey('currentBalance')), matching: find.text('96,000 Ks')), findsOneWidget);
    await tester.enterText(field('အကြွေး ကန့်သတ်ချက်'), '50000');
    await save(tester);
    expect(stored(c, SeedIds.thanHtun).creditLimit, 50000);
    expect(find.text('အကြွေးစာရင်း'), findsOneWidget, reason: 'saved, back on the debt screen (not blocked)');

    Future<String?> warningAtCheckout() async {
      c.read(cartProvider.notifier).clear();
      c.read(cartProvider.notifier).addProduct(db(c).products.firstWhere((p) => p.id == SeedIds.water)); // 600 Ks
      c.read(appRouterProvider).go(Routes.checkout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('အကြွေး'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ရွေးရန်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ဦးသန်းထွန်း').last);
      await tester.pumpAndSettle();
      final w = find.byKey(const ValueKey('creditLimitWarning'));
      return w.evaluate().isEmpty ? null : tester.widget<Text>(w).data;
    }

    final w = await warningAtCheckout();
    expect(w, allOf(isNotNull, contains('50,000'), contains('96,600')), reason: 'the lowered limit is used at sale time');

    await openEdit(tester, c, SeedIds.thanHtun);
    expect(tester.widget<EditableText>(field('အကြွေး ကန့်သတ်ချက်')).controller.text, '50000');
    await tester.enterText(field('အကြွေး ကန့်သတ်ချက်'), '');
    await save(tester);
    expect(stored(c, SeedIds.thanHtun).creditLimit, isNull);
    expect(await warningAtCheckout(), isNull, reason: 'no limit, no warning');
  });

  // ================================================================ TC-DEBT-NEW-7 seeded placeholder phones, Myanmar digits
  testWidgets('TC-DEBT-NEW-7 seeded placeholder phones: ဒေါ်ခင်မာ ("09 7xx xxx 102") can be edited without touching the '
      'phone (no error, no warning, phone kept); typing her placeholder for ဦးသန်းထွန်း warns with her name; a Myanmar-'
      'digit phone is stored in 0-9 and matched', (tester) async {
    final c = await boot(tester);
    await openEdit(tester, c, SeedIds.khinMa);
    expect(tester.widget<EditableText>(field('ဖုန်းနံပါတ်')).controller.text, '09 7xx xxx 102');
    await tester.enterText(field('လိပ်စာ'), 'ရပ်ကွက် (၃)');
    await save(tester);
    expect(find.text(dupTitle), findsNothing);
    final k = stored(c, SeedIds.khinMa);
    expect((k.phone, k.address), ('09 7xx xxx 102', 'ရပ်ကွက် (၃)'));

    await openEdit(tester, c, SeedIds.thanHtun);
    await tester.enterText(field('ဖုန်းနံပါတ်'), '09 7xx xxx 102');
    await save(tester);
    expect(find.text(dupTitle), findsOneWidget);
    expect(find.textContaining('“ဒေါ်ခင်မာ”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
    await tester.pumpAndSettle();
    expect(stored(c, SeedIds.thanHtun).phone, '09 4xx xxx 880', reason: 'cancel keeps the old number');

    await tester.enterText(field('ဖုန်းနံပါတ်'), '၀၉၇၉၀၀၁၁၀၀၁');
    await save(tester);
    expect(stored(c, SeedIds.thanHtun).phone, '09790011001');
    await openEdit(tester, c, SeedIds.zawMin);
    await tester.enterText(field('ဖုန်းနံပါတ်'), '09790011001');
    await save(tester);
    expect(find.textContaining('“ဦးသန်းထွန်း”'), findsOneWidget, reason: 'matched after Myanmar digits → 0-9');
  });

  // ================================================================ TC-DEBT-NEW-8 same number, other spacing
  testWidgets('TC-DEBT-NEW-8 the same number typed with spaces (the form\'s own hint is "09 xxx xxx xxx"): '
      '"09 790 011 002" for a customer while another has "09790011002" → the duplicate-phone warning shows (Add and Edit)',
      (tester) async {
    final c = await boot(tester);
    final t = DateTime.utc(2026, 11, 1);
    await c.read(customerServiceProvider).create(Customer(id: newId(), tenantId: c.read(tenantIdProvider),
        name: 'QA r11 ဒေါ်မြ', phone: '09790011002', createdAt: t, updatedAt: t));
    await openEdit(tester, c, SeedIds.zawMin);
    await tester.enterText(field('ဖုန်းနံပါတ်'), '09 790 011 002');
    await save(tester);
    final onEdit = find.text(dupTitle).evaluate().isNotEmpty;
    if (onEdit) {
      await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
      await tester.pumpAndSettle();
    }
    c.read(appRouterProvider).go(Routes.addCustomer);
    await tester.pumpAndSettle();
    await tester.enterText(field('အမည်'), 'QA r11 ကိုကို');
    await tester.enterText(field('ဖုန်းနံပါတ်'), '09-790-011-002');
    await save(tester);
    final onAdd = find.text(dupTitle).evaluate().isNotEmpty;
    expect((onEdit, onAdd), (true, true),
        reason: 'the same phone number in another format is not recognised as a duplicate (edit: $onEdit, add: $onAdd)');
  });

  // ================================================================ TC-DEBT-NEW-7 no English
  testWidgets('TC-DEBT-NEW-7 no English on the edit form, its errors and the duplicate-phone dialog', (tester) async {
    final c = await boot(tester);
    await openEdit(tester, c, SeedIds.thanHtun);
    final found = <String, List<String>>{};
    if (badStrings(tester, data: {'09 4xx xxx 880'}) case final b when b.isNotEmpty) found['form'] = b;
    await tester.enterText(field('အမည်'), '');
    await tester.enterText(field('မှတ်ချက်'), 'x' * 600);
    await save(tester);
    if (badStrings(tester, data: {'09 4xx xxx 880', 'x' * 600}) case final b when b.isNotEmpty) found['errors'] = b;
    await tester.enterText(find.byType(EditableText).first, 'ဦးသန်းထွန်း');
    await tester.enterText(field('မှတ်ချက်'), '');
    await tester.enterText(field('ဖုန်းနံပါတ်'), '09 7xx xxx 102');
    await save(tester);
    expect(find.text(dupTitle), findsOneWidget);
    if (badStrings(tester, data: {'09 7xx xxx 102'}) case final b when b.isNotEmpty) found['dialog'] = b;
    expect(found, isEmpty);
  });
}
