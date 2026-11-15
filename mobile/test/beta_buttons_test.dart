// BUG-46: the debtor screen's "ဖုန်းခေါ်ရန်" opens tel: (disabled with a hint when there is no phone) and
// "Viber သတိပေး" opens the share sheet with a Burmese reminder; the contact picker, Reports "Excel" and the
// checkout KBZPay/Wave payment-screenshot box are hidden for the beta; the sales-history "ယနေ့" is a label.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/money_format.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

class FakeDebtOutlet implements DebtOutlet {
  bool callResult = true;
  bool shareThrows = false;
  final calls = <Uri>[];
  final shared = <String>[];

  @override
  Future<bool> call(Uri uri) async {
    calls.add(uri);
    return callResult;
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    if (shareThrows) throw Exception('no share sheet');
    shared.add(text);
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('telUri', () {
    test('a stored phone in any form becomes digits', () {
      expect(telUri('09 790 011 002').toString(), 'tel:09790011002');
      expect(telUri('၀၉ ၇၉၀-၀၁၁ (၀၀၂)').toString(), 'tel:09790011002');
      expect(telUri('+95 9 790 011 002').toString(), 'tel:09790011002');
    });

    test('no phone → null', () {
      expect(telUri(''), isNull);
      expect(telUri(null), isNull);
      expect(telUri('   '), isNull);
      expect(telUri('-'), isNull);
    });
  });

  test('the reminder names the shop, the customer, the balance in Ks and the date, in Burmese', () {
    final text = debtReminderText(
      shop: 'ရွှေဝါ ကုန်စုံဆိုင်',
      customer: 'ကိုဇော်မင်း',
      balance: 12500,
      date: DateTime(2026, 11, 15, 10),
    );
    expect(text, contains('ရွှေဝါ ကုန်စုံဆိုင်'));
    expect(text, contains('ကိုဇော်မင်း'));
    expect(text, contains('12,500 Ks'));
    expect(text, contains('၁၅ နိုဝင်ဘာ ၂၀၂၆'));
    expect(text, contains('ပေးရန်ကျန်ငွေ'));
    expect(RegExp('[A-Za-z]').allMatches(text.replaceAll('Ks', '')), isEmpty, reason: 'no English but "Ks"');
  });

  Future<(ProviderContainer, FakeDebtOutlet)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outlet = FakeDebtOutlet();
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      debtOutletProvider.overrideWithValue(outlet),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, outlet);
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String route) async {
    c.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
  }

  Future<void> setPhone(WidgetTester tester, ProviderContainer c, String phone) async {
    await tester.runAsync(() async {
      final all = await val(c, customersProvider);
      final zaw = all.firstWhere((x) => x.id == SeedIds.zawMin);
      await c.read(customerServiceProvider).update(zaw.copyWith(phone: phone));
    });
    await tester.pumpAndSettle();
  }

  Finder callButton() => find.byKey(const ValueKey('debtCall'));

  group('debtor screen', () {
    testWidgets('"ဖုန်းခေါ်ရန်" opens tel: with the customer\'s phone', (tester) async {
      final (c, outlet) = await boot(tester);
      await setPhone(tester, c, '၀၉ ၇၉၀ ၀၁၁ ၀၀၂');
      await go(tester, c, Routes.customer(SeedIds.zawMin));
      expect(find.text(debtNoPhoneHint), findsNothing);
      await tester.tap(callButton());
      await tester.pumpAndSettle();
      expect(outlet.calls, [Uri.parse('tel:09790011002')]);
      expect(find.text(debtCallFailedText), findsNothing);
    });

    testWidgets('the dialer cannot open → Burmese message', (tester) async {
      final (c, outlet) = await boot(tester);
      outlet.callResult = false;
      await setPhone(tester, c, '09790011002');
      await go(tester, c, Routes.customer(SeedIds.zawMin));
      await tester.tap(callButton());
      await tester.pumpAndSettle();
      expect(find.text(debtCallFailedText), findsOneWidget);
    });

    testWidgets('no phone → "ဖုန်းခေါ်ရန်" is disabled and says why', (tester) async {
      final (c, outlet) = await boot(tester);
      final handle = tester.ensureSemantics();
      await setPhone(tester, c, '');
      await go(tester, c, Routes.customer(SeedIds.zawMin));
      expect(find.text(debtNoPhoneHint), findsOneWidget, reason: 'visible hint under the name');
      expect(
        tester.getSemantics(find.bySemanticsLabel(debtCallLabel)),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, hint: debtNoPhoneHint),
      );
      await tester.tap(callButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(outlet.calls, isEmpty);
      handle.dispose();
    });

    testWidgets('"Viber သတိပေး" opens the share sheet with the reminder for this customer', (tester) async {
      final (c, outlet) = await boot(tester);
      await go(tester, c, Routes.customer(SeedIds.zawMin));
      final account = (await tester.runAsync(() async {
        final all = await val(c, customerAccountsProvider);
        return all.firstWhere((a) => a.id == SeedIds.zawMin);
      }))!;
      expect(account.balance, greaterThan(0), reason: 'seed: ကိုဇော်မင်း owes money');
      await tester.tap(find.text(debtRemindLabel));
      await tester.pumpAndSettle();
      expect(outlet.shared, hasLength(1));
      final text = outlet.shared.single;
      expect(text, contains(c.read(sessionProvider).shopName));
      expect(text, contains('ကိုဇော်မင်း'));
      expect(text, contains(formatKs(account.balance)));
      expect(text, contains(mmLongDate(DateTime.now())));
    });

    testWidgets('"Viber သတိပေး" share fails → Burmese message', (tester) async {
      final (c, outlet) = await boot(tester);
      outlet.shareThrows = true;
      await go(tester, c, Routes.customer(SeedIds.zawMin));
      await tester.tap(find.text(debtRemindLabel));
      await tester.pumpAndSettle();
      expect(find.text(debtRemindFailedText), findsOneWidget);
    });
  });

  group('hidden for the beta', () {
    testWidgets('Add Customer: no contact picker', (tester) async {
      final (c, _) = await boot(tester);
      await go(tester, c, Routes.addCustomer);
      final handle = tester.ensureSemantics();
      expect(find.text('09 xxx xxx xxx'), findsOneWidget, reason: 'the phone field is still there');
      expect(find.bySemanticsLabel('ဖုန်းစာအုပ်ထဲက ရွေးရန်'), findsNothing);
      handle.dispose();
    });

    testWidgets('Reports: no "Excel"', (tester) async {
      final (c, _) = await boot(tester);
      await go(tester, c, Routes.reports);
      expect(find.text('အစီရင်ခံစာ'), findsWidgets);
      expect(find.text('Excel'), findsNothing);
    });

    for (final method in ['KBZPay', 'WavePay']) {
      testWidgets('checkout $method: no payment-screenshot box', (tester) async {
        final (c, _) = await boot(tester);
        final p = (await tester.runAsync(() => val(c, productsProvider)))!.first.product;
        c.read(cartProvider.notifier).addProduct(p);
        await go(tester, c, Routes.checkout);
        await tester.tap(find.text(method).first);
        await tester.pumpAndSettle();
        expect(find.textContaining('ငွေလွှဲပြေစာ ပုံ'), findsNothing);
        expect(find.text('+ ဓာတ်ပုံ ထည့်မယ်'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sales history: "ယနေ့" is a label, not a button', (tester) async {
      final (c, _) = await boot(tester);
      await go(tester, c, Routes.sales);
      expect(find.text('ယနေ့'), findsWidgets);
      final label = find.ancestor(of: find.text('ယနေ့').first, matching: find.byType(InkWell));
      expect(label, findsNothing);
    });
  });
}
