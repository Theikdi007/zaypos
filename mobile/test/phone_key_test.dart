import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/phone.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// BUG-34: one phone normalizer (Myanmar digits → 0-9, spaces/dashes/dots dropped, +959/959 → 09) for every place
/// phones are compared or searched: the duplicate-phone warning, customer search and OTP sign-in.
void main() {
  group('phoneKey', () {
    test('the same number in every way it is written gives one key', () {
      for (final input in [
        '09790011002', '09 790 011 002', '09-790-011-002', '09.790.011.002', '+959790011002', '+95 9 790 011 002',
        '959790011002', '95-9790-011002', '၀၉၇၉၀၀၁၁၀၀၂', '+၉၅၉ ၇၉၀ ၀၁၁ ၀၀၂', ' 09 (790) 011-002 ',
      ]) {
        expect(phoneKey(input), '09790011002', reason: input);
      }
    });

    test('other text keeps its shape; empty matches nothing', () {
      expect(phoneKey('01 234 567'), '01234567');
      expect(phoneKey('790 011'), '790011');
      expect(phoneKey(null), '');
      expect(samePhone('', ''), isFalse);
      expect(samePhone(null, '09790011002'), isFalse);
      expect(samePhone('09 790 011 002', '+959790011002'), isTrue);
      expect(samePhone('09790011002', '09790011003'), isFalse);
    });

    test('normalizeMmPhone (OTP sign-in) is built on the same key', () {
      for (final input in ['09.790.011.002', '+၉၅၉၇၉၀၀၁၁၀၀၂', '9 790 011 002', '959-790-011-002']) {
        expect(normalizeMmPhone(input), '+959790011002', reason: input);
      }
      expect(normalizeMmPhone('01 234 567'), isNull);
    });

    test('sign-in: the owner stored as E.164 is the same shop however the number is written', () async {
      final db = memoryDb();
      addTearDown(db.close);
      await db.writeState(LocalStateKeys.ownerTenantId, 't-1');
      await db.writeState(LocalStateKeys.ownerPhone, '+959790011002');
      await db.writeState(LocalStateKeys.ownerDemo, 'false');
      final local = LocalData(db);
      expect(await local.check('+959790011002'), SignInCheck.sameShop);
      expect(await local.check('09 790 011 002'), SignInCheck.sameShop);
      expect(await local.check('+959790011003'), isNot(SignInCheck.sameShop));
    });
  });

  group('screens', () {
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

    Future<Customer> add(ProviderContainer c, String name, String phone) async {
      final t = DateTime.utc(2026, 11, 1);
      final cu = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: name, phone: phone, createdAt: t, updatedAt: t);
      await c.read(customerServiceProvider).create(cu);
      return cu;
    }

    Finder field(String label) => find.descendant(of: find.bySemanticsLabel(label), matching: find.byType(EditableText));

    testWidgets('duplicate warning on Add and Edit: spaces, dashes, dots and +959 are the same number', (tester) async {
      final c = await boot(tester);
      await add(c, 'ဒေါ်မြ', '09790011002');
      final other = await add(c, 'ကိုဘ', '09790011099');

      for (final typed in ['09 790 011 002', '09-790-011-002', '09.790.011.002', '+959790011002', '959 790 011 002']) {
        c.read(appRouterProvider).go(Routes.addCustomer);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).at(0), 'ကိုစီ');
        await tester.enterText(find.byType(EditableText).at(1), typed);
        await tester.tap(find.text('သိမ်းမယ်'));
        await tester.pumpAndSettle();
        expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsOneWidget, reason: 'add: $typed');
        expect(find.textContaining('“ဒေါ်မြ”'), findsOneWidget, reason: typed);
        await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
        await tester.pumpAndSettle();
      }

      c.read(appRouterProvider).go(Routes.customer(other.id));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
      await tester.pumpAndSettle();
      await tester.enterText(field('ဖုန်းနံပါတ်'), '+95 9-790-011-002');
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsOneWidget, reason: 'edit');
    });

    testWidgets('edit: re-writing the own number with spaces is not a change (no warning)', (tester) async {
      final c = await boot(tester);
      await add(c, 'ဒေါ်မြ', '09790011002');
      final b = await add(c, 'ကိုဘ', '09 790 011 002'); // already shares it (saved anyway earlier)
      c.read(appRouterProvider).go(Routes.customer(b.id));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
      await tester.pumpAndSettle();
      await tester.enterText(field('ဖုန်းနံပါတ်'), '09790011002');
      await tester.tap(find.text('သိမ်းမယ်'));
      await tester.pumpAndSettle();
      expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsNothing);
    });

    testWidgets('customer search finds the number however it is typed or stored', (tester) async {
      final c = await boot(tester);
      await add(c, 'ဒေါ်မြ ဖုန်းတူ', '09 790 011 002');
      await add(c, 'ကိုဘ ဖုန်းကွဲ', '09790022003');
      c.read(appRouterProvider).go(Routes.customers);
      await tester.pumpAndSettle();
      final tabs = find.text('အားလုံး');
      if (tabs.evaluate().isNotEmpty) {
        await tester.tap(tabs.first); // customers without debt are on the "all" tab
        await tester.pumpAndSettle();
      }
      for (final q in ['09790011002', '+959790011', '959-790-011', '၀၉၇၉၀ ၀၁၁', '790.011']) {
        await tester.enterText(find.byType(EditableText).first, q);
        await tester.pumpAndSettle();
        expect(find.textContaining('ဒေါ်မြ ဖုန်းတူ'), findsOneWidget, reason: q);
        expect(find.textContaining('ကိုဘ ဖုန်းကွဲ'), findsNothing, reason: q);
      }
      await tester.enterText(find.byType(EditableText).first, 'ကိုဘ');
      await tester.pumpAndSettle();
      expect(find.textContaining('ကိုဘ ဖုန်းကွဲ'), findsOneWidget, reason: 'names still match');
    });
  });
}
