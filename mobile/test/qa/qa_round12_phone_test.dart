// QA round 12 — 205c5d7 (BUG-34), adversarial: customer search with partial numbers and every way a number is written or
// stored, and the duplicate-phone warning when the OTHER customer's number is stored with "+95 9 …" or Myanmar digits.
//
// Developer hand-over: "customer search ('09 790-011' and '+959790011' find the customer stored as '09790011002')";
// phone.dart: "Anything else (a landline, a partial number typed into search) is returned with only those steps applied."
// The developer's m/phone_key_test.dart searches with prefixes and a middle part ("790.011"). These search with the LAST
// digits of a number, which is how a shop finds a customer from a receipt or a missed call.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
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

  Future<void> add(ProviderContainer c, String name, String phone) async {
    final t = DateTime.utc(2026, 11, 1);
    await c.read(customerServiceProvider).create(
        Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: name, phone: phone, createdAt: t, updatedAt: t));
  }

  Finder field(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), matching: find.byType(EditableText));
  const dupTitle = 'ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ';

  Future<void> openAllTab(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.customers);
    await tester.pumpAndSettle();
    await tester.tap(find.text('အားလုံး').first); // customers without debt are on the "all" tab
    await tester.pumpAndSettle();
  }

  // ================================================================ TC-DEBT-NEW-9 search by partial numbers
  testWidgets('TC-DEBT-NEW-9 customer search with partial numbers: the last digits, a middle part, "+95 9 …" and Myanmar '
      'digits find the customer, whichever way the number was stored', (tester) async {
    final c = await boot(tester);
    await add(c, 'QA r12 ကိုစိုး', '09 777 959 123'); // a number with "959" inside it
    await add(c, 'QA r12 ဒေါ်နု', '+95 9 790 011 002'); // stored in the international form
    await add(c, 'QA r12 မမြင့်', '၀၉၄၂၀၁၂၃၄၅၆'); // typed in Myanmar digits (the form keeps it as 0-9)
    await openAllTab(tester, c);

    final cases = <String, String>{
      // last digits / middle parts
      '123': 'QA r12 ကိုစိုး', '9123': 'QA r12 ကိုစိုး', '959123': 'QA r12 ကိုစိုး', '959 123': 'QA r12 ကိုစိုး',
      '777 959': 'QA r12 ကိုစိုး', '၉၅၉၁၂၃': 'QA r12 ကိုစိုး',
      '011002': 'QA r12 ဒေါ်နု', '0979001': 'QA r12 ဒေါ်နု', '+95 9 790': 'QA r12 ဒေါ်နု', '+959790011002': 'QA r12 ဒေါ်နု',
      '၀၉၇၉၀ ၀၁၁': 'QA r12 ဒေါ်နု',
      '0942012': 'QA r12 မမြင့်', '+95 9 420 123 456': 'QA r12 မမြင့်', '၄၅၆': 'QA r12 မမြင့်',
    };
    final missed = <String>[];
    for (final MapEntry(key: q, value: name) in cases.entries) {
      await tester.enterText(find.byType(EditableText).first, q);
      await tester.pumpAndSettle();
      if (find.textContaining(name).evaluate().isEmpty) missed.add(q);
    }
    // ignore: avoid_print
    print('TC-DEBT-NEW-9 queries that do not find the customer: $missed');
    expect(missed, isEmpty, reason: 'each query is part of the customer\'s number');
  });

  // ================================================================ TC-DEBT-NEW-10 duplicate warning vs the other's stored form
  testWidgets('TC-DEBT-NEW-10 duplicate-phone warning when the OTHER customer\'s number is stored as "+95 9 …" or in Myanmar '
      'digits; editing a customer and re-writing the own number in another form gives no warning', (tester) async {
    final c = await boot(tester);
    await add(c, 'QA r12 ဒေါ်နု', '+95 9 790 011 002');
    await add(c, 'QA r12 ကိုအောင်', '09 (790) 011-003');
    final seen = <String, bool>{};
    for (final (typed, other) in [
      ('09790011002', 'QA r12 ဒေါ်နု'),
      ('၀၉၇၉၀၀၁၁၀၀၂', 'QA r12 ဒေါ်နု'),
      ('959.790.011.003', 'QA r12 ကိုအောင်'),
    ]) {
      c.read(appRouterProvider).go(Routes.addCustomer);
      await tester.pumpAndSettle();
      await tester.enterText(field('အမည်'), 'QA r12 အသစ်');
      await tester.enterText(field('ဖုန်းနံပါတ်'), typed);
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      seen[typed] = find.text(dupTitle).evaluate().isNotEmpty && find.textContaining('“$other”').evaluate().isNotEmpty;
      if (find.text(dupTitle).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
        await tester.pumpAndSettle();
      }
    }
    expect(seen, {'09790011002': true, '၀၉၇၉၀၀၁၁၀၀၂': true, '959.790.011.003': true});

    // own number: seeded "ကိုဇော်မင်း" re-typed in the international form → no warning, saved
    c.read(appRouterProvider).go(Routes.customer(SeedIds.zawMin));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
    await tester.pumpAndSettle();
    final own = tester.widget<EditableText>(field('ဖုန်းနံပါတ်')).controller.text;
    final digits = own.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^09\d{7,9}$').hasMatch(digits)) {
      await tester.enterText(field('ဖုန်းနံပါတ်'), '+95 ${digits.substring(1)}');
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      expect(find.text(dupTitle), findsNothing, reason: 'own number "$own" re-written as +95 …');
    } else {
      // the seed uses a masked number ("09 7xx …"): only check that saving it unchanged gives no warning
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      expect(find.text(dupTitle), findsNothing, reason: 'own number "$own" unchanged');
    }
  });
}
