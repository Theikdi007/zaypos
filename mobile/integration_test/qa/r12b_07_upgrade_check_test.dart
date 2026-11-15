// QA round 12b — upgrade check, part 2 (TC-UX-NEW-6 on a device): this build is installed OVER the round-8 build
// (flutter drive installs without deleting the app) on the phone seeded by r12b_07_upgrade_seed_r8_test.dart.
// Expect: it opens locked (session kept), the old PIN unlocks, schema v2, nothing lost, "စစ်ရန်" shows the
// duplicate-barcode issue in Burmese.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';

import 'qa_harness.dart';

void main() {
  qaBinding();

  testWidgets('installed over round 8: opens, nothing lost, "စစ်ရန်" in Burmese', (tester) async {
    final app = await launchApp(tester);
    final c = app.container;
    final version = (await app.db.customSelect('PRAGMA user_version').getSingle()).data.values.first;
    note('after upgrade: status=${c.read(authControllerProvider).status}, PRAGMA user_version=$version');
    await shot(tester, 'upgrade_head_first_open');
    expect(c.read(authControllerProvider).status, AuthStatus.locked, reason: 'the session survives the upgrade');
    await unlockIfLocked(tester, app, pin: '222222');
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(version, 2);

    c.listen(productsProvider, (_, _) {});
    c.listen(salesProvider, (_, _) {});
    c.listen(customersProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));
    final products = (c.read(productsProvider).value ?? const []).map((p) => p.product.name).toList();
    final customers = (c.read(customersProvider).value ?? const []).map((x) => x.name).toList();
    final sales = c.read(salesProvider).value ?? const [];
    note('after upgrade: ${products.length} products (r8 ones: ${products.where((n) => n.contains('r8')).toList()}), '
        'customers $customers, ${sales.length} sales');
    expect(products, containsAll(['QA r12b r8 Mirinda can', 'QA r12b r8 Fanta can', 'QA r12b ဆပ်ပြာ']));
    expect(customers, contains('QA r12b r8 Ko Aung'));

    await syncNowViaUi(tester, app);
    await shot(tester, 'upgrade_head_settings_sync');
    app.router.go(Routes.syncReview);
    await settle(tester);
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, 'upgrade_head_sync_review');
    final shown = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    note('"စစ်ရန်" texts after the upgrade: $shown');
    expect(find.textContaining('is also used by'), findsNothing, reason: 'no stored English text');
    expect(find.textContaining('Barcode'), findsWidgets, reason: 'the duplicate-barcode issue is listed');
    // TC-UX-NEW-6 expected result: after the pull the issue names the barcode and both products. Failed on the device in
    // logs/r12b_07_B_upgrade_head_run1.log (the issue created before the upgrade is never re-sent) → BUG-43.
    expect(find.textContaining('8850000099003'), findsWidgets, reason: 'after the pull the issue names the barcode (BUG-43)');
  });
}
