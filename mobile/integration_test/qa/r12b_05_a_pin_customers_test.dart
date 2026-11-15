// QA round 12b — phone A after phone B reset the PIN (r12b_04 reset step, new PIN 222222).
// TC-AUTH-NEW-3 / TC-PIN: on the Login screen the OLD PIN is refused and the new one opens the same shop.
// TC-DEBT-NEW-8 / -10: add "09 790 011 002", then another customer typing "09790011002" → the duplicate dialog names
// the first one; search "790 011" finds it. Also: the sale screen's "ပြေစာ ပို့မယ်" button (part of TC-POS-11).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';

import 'qa_harness.dart';

void main() {
  qaBinding();

  testWidgets('A: old PIN refused, new PIN works; duplicate phone + search; sale "ပြေစာ ပို့မယ်"', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    if (find.text('ဝင်မယ်').evaluate().isNotEmpty) {
      await type(tester, field('ဖုန်းနံပါတ်'), '9 790 917 051');
      await type(tester, field('PIN နံပါတ်'), '111111');
      await tapText(tester, 'ဝင်မယ်');
      await wait(tester, const Duration(seconds: 4));
      final status = app.container.read(authControllerProvider).status;
      note('old PIN 111111 on Login: status=$status');
      expect(status, AuthStatus.signedOut, reason: 'the old PIN must be refused after the reset on phone B');
      await shot(tester, 'auth3_A_old_pin_refused');
      await signInIfSignedOut(tester, app, '9 790 917 051', pin: '222222');
    }
    expect(app.container.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(app.container.read(sessionProvider).shopName, 'QA r12b ကုန်စုံ');
    await shot(tester, 'auth3_A_new_pin_dashboard');

    // ---------------------------------------------------------------- TC-DEBT-NEW-8 / -10
    Future<void> addCustomer(String name, String phone) async {
      app.router.go(Routes.addCustomer);
      await settle(tester);
      await type(tester, field('အမည်'), name);
      await type(tester, field('ဖုန်းနံပါတ်'), phone);
      await tapText(tester, 'သိမ်းမယ်', last: true);
      await wait(tester, const Duration(seconds: 1));
    }

    await addCustomer('QA r12b Daw Mya', '09 790 011 002');
    if (find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ').evaluate().isNotEmpty) {
      note('Daw Mya already saved by the first run of this file; dialog closed');
      await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
      await settle(tester);
    }
    await addCustomer('QA r12b U Ba', '09790011002');
    final dialog = find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ');
    expect(dialog, findsOneWidget, reason: 'duplicate-phone dialog');
    expect(find.textContaining('QA r12b Daw Mya'), findsWidgets, reason: 'the dialog names the first customer');
    await shot(tester, 'debt8_duplicate_phone_dialog');
    await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
    await settle(tester);

    app.router.go(Routes.customers);
    await settle(tester);
    await tapText(tester, 'အားလုံး'); // the default tab lists only customers with debt
    await type(tester, find.byType(EditableText), '790 011');
    await wait(tester, const Duration(seconds: 1));
    expect(find.text('QA r12b Daw Mya'), findsOneWidget, reason: 'search "790 011"');
    expect(find.text('QA r12b U Ba'), findsNothing, reason: 'the duplicate was not saved');
    await shot(tester, 'debt8_search_790_011');

    // ---------------------------------------------------------------- sale screen "ပြေစာ ပို့မယ်"
    final sales = app.container.read(salesProvider).value ?? const [];
    note('sales on A: ${sales.map((s) => '#${s.no} ${s.total} voided=${s.voided}').toList()}');
    if (sales.isNotEmpty) {
      app.router.go(Routes.sale(sales.first.id));
      await settle(tester);
      final before = app.router.location;
      await tapText(tester, 'ပြေစာ ပို့မယ်');
      await wait(tester, const Duration(seconds: 2));
      final sheets = find.byType(BottomSheet).evaluate().length + find.byType(Dialog).evaluate().length;
      note('sale detail "ပြေစာ ပို့မယ်": route $before → ${app.router.location}, sheets/dialogs=$sheets');
      await shot(tester, 'pos11_sale_detail_send_receipt_tap');
    }
  });
}
