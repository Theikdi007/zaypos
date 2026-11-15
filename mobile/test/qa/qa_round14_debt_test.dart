// QA round 14 — findings around the BUG-46 fix (3f89623), fake repositories, 390×844.
//  TC-DEBT-NEW-12: "Viber သတိပေး" on a customer who owes nothing. A debt reminder for "0 Ks" (or a negative amount after an
//                  overpayment) must not be sent: the button is hidden / disabled, or nothing is shared.
//  TC-UX-NEW-13:   screen reader. An ENABLED button must expose the semantics tap action, otherwise VoiceOver / TalkBack
//                  "activate" has nothing to call. AppIconButton (and the bottom nav, PIN keypad, POS scan, restock, qty)
//                  wrap the InkWell in Semantics(excludeSemantics: true) without an onTap.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/data/customer_repository.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

class _Outlet implements DebtOutlet {
  final calls = <Uri>[];
  final shared = <String>[];
  @override
  Future<bool> call(Uri uri) async {
    calls.add(uri);
    return true;
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) async => shared.add(text);
}

void main() {
  setUpAll(loadAppFonts);

  Future<(ProviderContainer, _Outlet)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outlet = _Outlet();
    final c = ProviderContainer(overrides: [...fakeRepositoryOverrides, debtOutletProvider.overrideWithValue(outlet)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, outlet);
  }

  testWidgets('TC-DEBT-NEW-12 "Viber သတိပေး" for a customer who owes nothing sends no "0 Ks" debt reminder', (tester) async {
    final (c, outlet) = await boot(tester);
    final now = DateTime.now().toUtc();
    const id = '01a1aaaa-0000-7000-8000-000000000012';
    await tester.runAsync(() => c.read(customerRepositoryProvider).add(Customer(
          id: id,
          tenantId: c.read(tenantIdProvider),
          name: 'QA r14 အကြွေးမရှိ',
          phone: '09 790 011 012',
          createdAt: now,
          updatedAt: now,
        )));
    await tester.pumpAndSettle();
    final acc = (await tester.runAsync(() => val(c, customerAccountsProvider)))!.firstWhere((a) => a.id == id);
    expect(acc.balance, 0);
    c.read(appRouterProvider).go(Routes.customer(id));
    await tester.pumpAndSettle();
    final btn = find.text(debtRemindLabel);
    if (btn.evaluate().isNotEmpty) {
      await tester.tap(btn, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    // ignore: avoid_print
    print('TC-DEBT-NEW-12 balance=${acc.balance} button shown=${btn.evaluate().isNotEmpty} shared=${outlet.shared}');
    expect(outlet.shared, isEmpty, reason: 'a reminder for a debt of 0 Ks must not be offered');
  });

  testWidgets('TC-UX-NEW-13 enabled buttons can be activated by a screen reader (semantics tap action)', (tester) async {
    final (c, _) = await boot(tester);
    final handle = tester.ensureSemantics();
    final missing = <String>[];
    void checkNode(String what, Finder f) {
      final d = tester.getSemantics(f).getSemanticsData();
      final ok = d.hasAction(SemanticsAction.tap);
      // ignore: avoid_print
      print('TC-UX-NEW-13 $what: label="${d.label}" button=${d.flagsCollection.isButton} '
          'enabled=${d.flagsCollection.isEnabled} tap=$ok');
      if (!ok) missing.add(what);
    }

    c.read(appRouterProvider).go(Routes.customer(SeedIds.zawMin));
    await tester.pumpAndSettle();
    checkNode('debtor "ဖုန်းခေါ်ရန်" (phone present)', find.bySemanticsLabel(debtCallLabel));
    checkNode('debtor "Viber သတိပေး" (control: PrimaryButton)', find.bySemanticsLabel(RegExp(debtRemindLabel)));
    c.read(appRouterProvider).go(Routes.dashboard);
    await tester.pumpAndSettle();
    checkNode('bottom nav "ပစ္စည်း"', find.bySemanticsLabel('ပစ္စည်း').last);
    expect(missing, isEmpty, reason: 'enabled buttons without a semantics tap action: $missing');
    handle.dispose();
  });
}
