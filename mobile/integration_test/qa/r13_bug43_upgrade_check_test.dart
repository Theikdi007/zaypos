// QA round 13 — BUG-43 upgrade check, part 2 (TC-UX-NEW-6 on a device): this build is installed OVER the round-8 build
// seeded by r13_bug43_upgrade_seed_r8_test.dart (flutter drive installs without deleting the app). The API is started
// again before this run.
// Expect: the v1→v2 migration resets the pull cursor to "0"; after a sync both duplicate-barcode issues (the r13 one and
// round 12b's, both pulled under v1) name their barcode and products; the full re-pull duplicates nothing (same row counts,
// same stock), and the unsent offline product is sent, not lost.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';

import 'qa_harness.dart';

Future<int> count(QaApp app, String sql) async =>
    (await app.db.customSelect(sql).getSingle()).data.values.first as int;

void main() {
  qaBinding();

  testWidgets('installed over round 8: cursor reset, issues get their details, nothing duplicated or lost', (tester) async {
    final app = await launchApp(tester);
    // Read before anything can sync (the app opens locked; sync starts after unlock).
    final cursor0 = (await app.db.customSelect("SELECT value FROM syncState WHERE key = 'pullCursor'").getSingleOrNull())
        ?.data['value'];
    final version = (await app.db.customSelect('PRAGMA user_version').getSingle()).data.values.first;
    final seed = File('$qaDir/r13_seed.txt').readAsStringSync();
    note('after upgrade, before unlock: user_version=$version pullCursor=$cursor0 status=${app.container.read(authControllerProvider).status}');
    note('seed (r8): $seed');
    expect(version, 2);
    expect(cursor0, '0', reason: 'BUG-43: the v1→v2 migration resets the pull cursor');
    expect(app.container.read(authControllerProvider).status, AuthStatus.locked);
    await unlockIfLocked(tester, app, pin: '222222');

    await syncNowViaUi(tester, app);
    await wait(tester, const Duration(seconds: 2));
    await syncNowViaUi(tester, app);

    Future<String> counts() async {
      final products = await count(app, 'SELECT COUNT(*) FROM products WHERE deletedAt IS NULL');
      final customers = await count(app, 'SELECT COUNT(*) FROM customers WHERE deletedAt IS NULL');
      final sales = await count(app, 'SELECT COUNT(*) FROM sales');
      final issues = await count(app, 'SELECT COUNT(*) FROM syncIssues');
      final moves = await count(app, 'SELECT COUNT(*) FROM stockMovements WHERE deletedAt IS NULL');
      final stock = await count(app, 'SELECT COALESCE(SUM(qtyMilli), 0) FROM stockMovements WHERE deletedAt IS NULL');
      final debts = await count(app, 'SELECT COUNT(*) FROM debtEntries WHERE deletedAt IS NULL');
      return 'products=$products customers=$customers sales=$sales issues=$issues moves=$moves stockSum=$stock debts=$debts';
    }

    final after = await counts();
    final outboxLeft = await count(app, "SELECT COUNT(*) FROM outbox");
    final cursor1 = (await app.db.customSelect("SELECT value FROM syncState WHERE key = 'pullCursor'").getSingle()).data['value'];
    final offline = await count(app, "SELECT COUNT(*) FROM products WHERE name = 'QA r13 r8 offline unsent' AND deletedAt IS NULL");
    final dataNull = await count(app, 'SELECT COUNT(*) FROM syncIssues WHERE data IS NULL');
    note('after two syncs: $after; outbox rows left=$outboxLeft; pullCursor=$cursor1; offline product rows=$offline; '
        'issues with data NULL=$dataNull');

    app.router.go(Routes.syncReview);
    await settle(tester);
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, 'r13_upgrade_head_sync_review');
    final shown = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    note('"စစ်ရန်" texts after the upgrade: $shown');

    // Same rows as before the upgrade (seed counts minus its cursor/outbox fields).
    final seedCounts = RegExp(r'products=\S+ customers=\S+ sales=\S+ issues=\S+').firstMatch(seed)![0]!;
    final seedTail = RegExp(r'moves=\S+ stockSum=\S+ debts=\S+').firstMatch(seed)![0]!;
    expect(after, '$seedCounts $seedTail', reason: 'the full re-pull neither duplicates nor drops rows');
    // Earlier tries left products with this name on the server; the seed records how many rows it had (incl. the unsent one).
    expect('offline=$offline', RegExp(r'offline=\d+').firstMatch(seed)![0], reason: 'the unsent product survives the reset re-pull');
    expect(outboxLeft, 0, reason: 'the unsent product is sent');
    expect(cursor1, isNot('0'));
    expect(dataNull, 0, reason: 'every issue got its data');
    expect(find.textContaining('8850000099013'), findsWidgets, reason: 'r13 issue names its barcode');
    // Round 12b's issue may be resolved by now (history list); its stored data must name the barcode.
    final r12b = await count(app, "SELECT COUNT(*) FROM syncIssues WHERE data LIKE '%8850000099003%'");
    note('issues whose data names 8850000099003: $r12b');
    expect(r12b, greaterThan(0), reason: 'round-12b issue (pulled under v1) got its data');
  });
}
