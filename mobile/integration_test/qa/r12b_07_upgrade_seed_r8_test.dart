// QA round 12b — upgrade check, part 1. RUNS ON THE ROUND-8 BUILD (e7cd138, Drift schema v1), not on this tree:
// copy this file and qa_harness.dart into a worktree of e7cd138 (integration_test/qa/), add integration_test to its
// dev_dependencies, and run it with run_qa.sh on a phone whose app was deleted first.
// Phone B signs in to shop A, adds two products with the SAME barcode (the server answers with a DuplicateBarcode
// issue → "စစ်ရန် (1)"), sells once, adds a customer and syncs. Part 2 (r12b_07_upgrade_check_test.dart) installs this
// build over it.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

import 'qa_harness.dart';

void main() {
  qaBinding();

  testWidgets('round-8 build: data + a "စစ်ရန်" entry before the upgrade', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    await signInIfSignedOut(tester, app, '9 790 917 051', pin: '222222');
    final c = app.container;
    final tenant = c.read(tenantIdProvider);
    final t = nowUtc();
    for (final name in ['QA r12b r8 Mirinda can', 'QA r12b r8 Fanta can']) {
      await c.read(productServiceProvider).create(Product(
          id: newId(), tenantId: tenant, name: name, cost: 500, price: 800, category: 'အချိုရည်',
          barcode: '8850000099003', tint: 0, initial: 'M', createdAt: t, updatedAt: t));
    }
    await c.read(customerServiceProvider).create(
        Customer(id: newId(), tenantId: tenant, name: 'QA r12b r8 Ko Aung', phone: '09790011009', createdAt: t, updatedAt: t));
    await settle(tester);
    await syncNowViaUi(tester, app);
    await wait(tester, const Duration(seconds: 3));
    await syncNowViaUi(tester, app);
    await shot(tester, 'upgrade_r8_settings_before');
    app.router.go(Routes.syncReview);
    await settle(tester);
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, 'upgrade_r8_sync_review_before');
  });
}
