// QA round 13 — BUG-43 upgrade check, part 1. RUNS ON THE ROUND-8 BUILD (e7cd138, Drift schema v1), not on this tree:
// export e7cd138's mobile/ (git archive), add integration_test to its dev_dependencies, copy this file, qa_harness.dart and
// test_driver/integration_test.dart into it, and run it with run_qa.sh on a phone whose app was deleted first.
// Phone B signs in to shop A, adds two products with the SAME barcode 8850000099013 (→ a DuplicateBarcode issue), adds a
// customer and syncs (it also pulls round 12b's 8850000099003 issue, which the v1 schema stores without its data). Then the
// API is stopped and one product is added offline (an unsent unit across the upgrade). Counts go to $QA_DIR/r13_seed.txt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

import 'qa_harness.dart';

Future<int> count(QaApp app, String sql) async =>
    (await app.db.customSelect(sql).getSingle()).data.values.first as int;

void main() {
  qaBinding();

  testWidgets('round-8 build: data, two "စစ်ရန်" entries and one unsent product before the upgrade', (tester) async {
    final app = await launchApp(tester);
    final version = (await app.db.customSelect('PRAGMA user_version').getSingle()).data.values.first;
    note('build check: PRAGMA user_version=$version (round-8 build = 1)');
    expect(version, 1, reason: 'this must run on the round-8 build');
    await unlockIfLocked(tester, app, pin: '222222');
    await signInIfSignedOut(tester, app, '9 790 917 051', pin: '222222');
    final c = app.container;
    final tenant = c.read(tenantIdProvider);
    final t = nowUtc();
    for (final name in ['QA r13 r8 Coke can', 'QA r13 r8 Sprite can']) {
      await c.read(productServiceProvider).create(Product(
          id: newId(), tenantId: tenant, name: name, cost: 500, price: 800, category: 'အချိုရည်',
          barcode: '8850000099013', tint: 0, initial: 'C', createdAt: t, updatedAt: t));
    }
    await c.read(customerServiceProvider).create(
        Customer(id: newId(), tenantId: tenant, name: 'QA r13 r8 Ko Min', phone: '09790011019', createdAt: t, updatedAt: t));
    await settle(tester);
    await syncNowViaUi(tester, app);
    await wait(tester, const Duration(seconds: 3));
    await syncNowViaUi(tester, app);
    app.router.go(Routes.syncReview);
    await settle(tester);
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, 'r13_upgrade_r8_sync_review_before');

    // An unsent unit across the upgrade.
    await hostCmd(tester, 'api_stop');
    await c.read(productServiceProvider).create(Product(
        id: newId(), tenantId: tenant, name: 'QA r13 r8 offline unsent', cost: 100, price: 200, category: 'အချိုရည်',
        tint: 0, initial: 'O', createdAt: nowUtc(), updatedAt: nowUtc()));
    await wait(tester, const Duration(seconds: 2));

    final cursor = (await app.db.customSelect("SELECT value FROM syncState WHERE key = 'pullCursor'").getSingleOrNull())
        ?.data['value'];
    final products = await count(app, 'SELECT COUNT(*) FROM products WHERE deletedAt IS NULL');
    final customers = await count(app, 'SELECT COUNT(*) FROM customers WHERE deletedAt IS NULL');
    final sales = await count(app, 'SELECT COUNT(*) FROM sales');
    final issues = await count(app, 'SELECT COUNT(*) FROM syncIssues');
    final outbox = await count(app, 'SELECT COUNT(*) FROM outbox');
    final moves = await count(app, 'SELECT COUNT(*) FROM stockMovements WHERE deletedAt IS NULL');
    final stock = await count(app, 'SELECT COALESCE(SUM(qtyMilli), 0) FROM stockMovements WHERE deletedAt IS NULL');
    final debts = await count(app, 'SELECT COUNT(*) FROM debtEntries WHERE deletedAt IS NULL');
    final offline = await count(app, "SELECT COUNT(*) FROM products WHERE name = 'QA r13 r8 offline unsent' AND deletedAt IS NULL");
    final line = 'offline=$offline cursor=$cursor products=$products customers=$customers sales=$sales issues=$issues outbox=$outbox '
        'moves=$moves stockSum=$stock debts=$debts';
    note('r8 before upgrade: $line');
    File('$qaDir/r13_seed.txt').writeAsStringSync(line);
    expect(cursor, isNot(anyOf(isNull, '0')), reason: 'a real cursor before the upgrade');
    expect(outbox, greaterThan(0), reason: 'the offline product is unsent');
  });
}
