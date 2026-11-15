// QA round 14 — BUG-46 fix (3f89623) on the iOS simulator, real app (Drift "zaypos", shop A), REAL url_launcher and share_plus.
// The debt outlet is wrapped only to RECORD what the real PlatformDebtOutlet was asked to open and what it answered; every
// call goes through to the plugin unchanged.
//   1. no phone: a customer without a phone → "ဖုန်းခေါ်ရန်" disabled, hint text under the name and as the semantics hint
//      (what VoiceOver reads), tapping does nothing; long press shows the hint tooltip.
//   2. call: the debtor with a phone and the largest balance → tap → the tel: URI, the plugin's answer, what the app shows;
//      the host collects the iOS log lines about opening the URL (runner `syslog_tel`).
//   3. Viber: "Viber သတိပေး" → the system share sheet with the reminder text (recorded + screenshot). Ends with the sheet open.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/money_format.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';

import 'qa_harness.dart';

const noPhoneName = 'QA r14 ဖုန်းမရှိ';

class _Recording implements DebtOutlet {
  _Recording(this.real);
  final DebtOutlet real;
  final calls = <(Uri, bool)>[];
  final shared = <String>[];
  final shareErrors = <String>[];

  @override
  Future<bool> call(Uri uri) async {
    final ok = await real.call(uri);
    calls.add((uri, ok));
    note('outlet.call($uri) → $ok (real url_launcher)');
    return ok;
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    shared.add(text);
    note('outlet.shareText origin=$origin text=<<<$text>>>');
    try {
      await real.shareText(text, origin: origin);
      note('outlet.shareText returned (sheet closed)');
    } catch (e) {
      shareErrors.add('$e');
      note('outlet.shareText threw $e');
      rethrow;
    }
  }
}

void main() {
  qaBinding();

  testWidgets('BUG-46 debtor call / Viber reminder on the simulator', (tester) async {
    final rec = _Recording(const PlatformDebtOutlet());
    final app = await launchApp(tester, overrides: [debtOutletProvider.overrideWithValue(rec)]);
    await unlockIfLocked(tester, app, pin: '222222');
    final c = app.container;
    c.listen(customerAccountsProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));
    final sem = tester.ensureSemantics();

    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => problems.add('${d.exceptionAsString().split('\n').first} @ ${app.router.location}');
    addTearDown(() => FlutterError.onError = old);
    // Failures are collected and asserted at the end, after FlutterError.onError is restored (an check() failing while it
    // is replaced hides the real message behind a binding assertion).
    final failures = <String>[];
    void check(Object? actual, Object? expected, {String reason = ''}) {
      final m = wrapMatcher(expected);
      final state = <dynamic, dynamic>{};
      if (!m.matches(actual, state)) {
        final d = m.describeMismatch(actual, StringDescription(), state, false);
        failures.add('$reason: expected ${m.describe(StringDescription())}, actual $actual ($d)');
        note('CHECK FAILED $reason: actual $actual');
      }
    }

    String? snack() {
      final s = find.descendant(of: find.byType(SnackBar), matching: find.byType(Text));
      return s.evaluate().isEmpty ? null : (s.evaluate().first.widget as Text).data;
    }

    // ---------------------------------------------------------------- 1. customer without a phone
    var accounts = c.read(customerAccountsProvider).value ?? const [];
    if (!accounts.any((a) => a.name == noPhoneName)) {
      app.router.go(Routes.addCustomer);
      await settle(tester);
      await type(tester, field('အမည်'), noPhoneName);
      await tapText(tester, 'သိမ်းမယ်', last: true);
      await wait(tester, const Duration(seconds: 2));
      accounts = c.read(customerAccountsProvider).value ?? const [];
    }
    final np = accounts.firstWhere((a) => a.name == noPhoneName);
    note('no-phone customer ${np.id} phone="${np.customer.phone}" balance=${np.balance}');
    app.router.go(Routes.customer(np.id));
    await settle(tester);
    await waitFor(tester, find.text(noPhoneName), why: 'debt screen of the no-phone customer');
    final callBtn = find.byKey(const ValueKey('debtCall'));
    check(find.text(debtNoPhoneHint), findsOneWidget, reason: 'visible hint under the name');
    final node = tester.getSemantics(find.bySemanticsLabel(debtCallLabel));
    final d = node.getSemanticsData();
    note('no-phone call button semantics: label="${d.label}" hint="${d.hint}" '
        'isButton=${d.flagsCollection.isButton} enabled=${d.flagsCollection.isEnabled} '
        'actions tap=${d.hasAction(SemanticsAction.tap)}');
    check(d.label, debtCallLabel);
    check(d.hint, debtNoPhoneHint);
    check(d.hasAction(SemanticsAction.tap), isFalse, reason: 'disabled: VoiceOver cannot activate it');
    await shot(tester, 'r14_debt_nophone');
    await tester.tap(callBtn, warnIfMissed: false);
    await wait(tester, const Duration(seconds: 2));
    note('no-phone tap: outlet calls=${rec.calls.length}, snackbar="${snack()}"');
    check(rec.calls, isEmpty);
    check(snack(), isNull);
    await tester.longPress(callBtn, warnIfMissed: false);
    await wait(tester, const Duration(milliseconds: 800));
    note('long press tooltip visible: ${find.byType(Tooltip).evaluate().isNotEmpty} '
        'hint texts on screen=${find.text(debtNoPhoneHint).evaluate().length}');
    await shot(tester, 'r14_debt_nophone_longpress');
    await wait(tester, const Duration(seconds: 2));

    // ---------------------------------------------------------------- 2. call a debtor with a phone
    final withPhone = accounts.where((a) => telUri(a.customer.phone) != null && a.balance > 0).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    check(withPhone, isNotEmpty, reason: 'shop A has a debtor with a phone');
    final debtor = withPhone.first;
    final expectedUri = telUri(debtor.customer.phone)!;
    note('debtor ${debtor.name} phone="${debtor.customer.phone}" balance=${debtor.balance} → expected $expectedUri');
    app.router.go(Routes.customer(debtor.id));
    await settle(tester);
    await waitFor(tester, callBtn, why: 'debt screen');
    final d2 = tester.getSemantics(find.bySemanticsLabel(debtCallLabel)).getSemanticsData();
    note('call button semantics: label="${d2.label}" hint="${d2.hint}" enabled=${d2.flagsCollection.isEnabled} '
        'tap=${d2.hasAction(SemanticsAction.tap)}; hint text on screen=${find.text(debtNoPhoneHint).evaluate().length}');
    // No assertion here: the missing semantics tap action of AppIconButton is a separate finding (BUG-48, sweep audit).
    await shot(tester, 'r14_debt_call_before');
    await tester.tap(callBtn);
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (rec.calls.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await wait(tester, const Duration(milliseconds: 600));
    note('call: outlet calls=${rec.calls}, snackbar="${snack()}", route ${app.router.location}');
    await shot(tester, 'r14_debt_call_after');
    await hostCmd(tester, 'syslog_tel');
    check(rec.calls.map((e) => e.$1).toList(), [expectedUri]);
    await wait(tester, const Duration(seconds: 4)); // snackbar gone

    // ---------------------------------------------------------------- 3. Viber reminder
    final shop = c.read(sessionProvider).shopName;
    await tapText(tester, debtRemindLabel);
    final end2 = DateTime.now().add(const Duration(seconds: 8));
    while (rec.shared.isEmpty && DateTime.now().isBefore(end2)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await wait(tester, const Duration(seconds: 3));
    note('viber: shared=${rec.shared.length} errors=${rec.shareErrors} snackbar="${snack()}"');
    await shot(tester, 'r14_debt_viber_share_sheet');
    check(rec.shared, hasLength(1));
    final text = rec.shared.single;
    final today = mmLongDate(DateTime.now());
    note('reminder checks: shop "$shop"=${text.contains(shop)} customer=${text.contains(debtor.name)} '
        'balance "${formatKs(debtor.balance)}"=${text.contains(formatKs(debtor.balance))} date "$today"=${text.contains(today)}');
    check(text, contains(shop));
    check(text, contains(debtor.name));
    check(text, contains(formatKs(debtor.balance)));
    check(text, contains(today));
    check(rec.shareErrors, isEmpty);
    check(snack(), isNull, reason: 'no failure message while the sheet is up');

    note('layout/framework problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    FlutterError.onError = old;
    expect(problems, isEmpty);
    expect(failures, isEmpty);
    sem.dispose();
  });
}
