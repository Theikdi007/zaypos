// QA round 12b — ea3c59e (BUG-36) re-test, adversarial edge cases.
//
// phone.dart: phoneSearchKey = "phoneDigits, plus only an explicit leading '+95' → '0'; a bare leading '959' stays".
// customers_screen.dart: phoneKey(storedPhone).contains(phoneSearchKey(query)). Full-number comparisons keep phoneKey.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
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

  Future<void> openAllTab(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.customers);
    await tester.pumpAndSettle();
    await tester.tap(find.text('အားလုံး').first);
    await tester.pumpAndSettle();
  }

  const a = 'QA r12b ကိုစိုး'; // "09 777 959 123"
  const b = 'QA r12b ဒေါ်ခင်'; // stored "+95 9 777 959 124"
  const d = 'QA r12b ကိုလင်း'; // stored "959777959125" (no plus)
  const e = 'QA r12b မအေး'; // "09 420 111 222" (no 959 anywhere)

  Future<Map<String, Set<String>>> search(WidgetTester tester, List<String> queries) async {
    final out = <String, Set<String>>{};
    for (final q in queries) {
      await tester.enterText(find.byType(EditableText).first, q);
      await tester.pumpAndSettle();
      out[q] = {for (final n in [a, b, d, e]) if (find.textContaining(n).evaluate().isNotEmpty) n};
    }
    return out;
  }

  testWidgets('TC-DEBT-NEW-9 r12b: partial queries with "959", "+95 9 …" and Myanmar digits, against numbers stored as '
      '"09 …", "+95 9 …" and "959…"; names still match', (tester) async {
    final c = await boot(tester);
    await add(c, a, '09 777 959 123');
    await add(c, b, '+95 9 777 959 124');
    await add(c, d, '959777959125');
    await add(c, e, '09 420 111 222');
    await openAllTab(tester, c);

    final got = await search(tester, [
      '959', '959123', '၉၅၉၁၂၃', '959 124', '959-125', '+95 9 777', '+95977', '0977', '09777959125', '+959777959124',
      '၀၉၇၇၇', '222', 'ကိုစိုး', 'မအေး',
    ]);
    // ignore: avoid_print
    print('r12b partial: $got');
    expect(got, {
      '959': {a, b, d}, // only numbers that contain 959; "09 420 …" is not listed
      '959123': {a},
      '၉၅၉၁၂၃': {a},
      '959 124': {b},
      '959-125': {d},
      '+95 9 777': {a, b, d},
      '+95977': {a, b, d},
      '0977': {a, b, d},
      '09777959125': {d},
      '+959777959124': {b},
      '၀၉၇၇၇': {a, b, d},
      '222': {e},
      'ကိုစိုး': {a},
      'မအေး': {e},
    });
  });

  testWidgets('TC-DEBT-NEW-11 r12b probe: a FULL number typed in the international form without "+" ("959 777 959 123") '
      'finds the customer stored as "09 777 959 123"', (tester) async {
    final c = await boot(tester);
    await add(c, a, '09 777 959 123');
    await add(c, d, '959777959125');
    await openAllTab(tester, c);
    final got = await search(tester, ['959777959123', '959 777 959 123', '959777959125']);
    // ignore: avoid_print
    print('r12b full 959… query: $got');
    expect(got, {
      '959777959123': {a},
      '959 777 959 123': {a},
      '959777959125': {d},
    }, reason: 'a full Myanmar number written 959… is the same number as 09… (phoneKey / samePhone treat it so)');
  });

  testWidgets('BUG-36 r12b: the duplicate-phone warning still matches "959777959123" against the stored "09777959123" '
      '(and "+95 9 777 959 123")', (tester) async {
    final c = await boot(tester);
    await add(c, a, '09777959123');
    final seen = <String, bool>{};
    for (final typed in ['959777959123', '+95 9 777 959 123', '၉၅၉၇၇၇၉၅၉၁၂၃']) {
      c.read(appRouterProvider).go(Routes.addCustomer);
      await tester.pumpAndSettle();
      await tester.enterText(field('အမည်'), 'QA r12b အသစ်');
      await tester.enterText(field('ဖုန်းနံပါတ်'), typed);
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      final dup = find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ').evaluate().isNotEmpty;
      seen[typed] = dup && find.textContaining('“$a”').evaluate().isNotEmpty;
      if (dup) {
        await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
        await tester.pumpAndSettle();
      }
    }
    expect(seen, {'959777959123': true, '+95 9 777 959 123': true, '၉၅၉၇၇၇၉၅၉၁၂၃': true});
  });
}
