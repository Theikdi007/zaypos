// QA round 15: the iPhone simulator as the SECOND phone of the Android shop "QA r15 Android" (+959790917151, PIN 111111).
// Run with run_qa.sh (iOS runner, API on localhost:5076, scratch DB). It signs in, lets the first sync pull everything the
// Android emulator made, records what arrived (incl. the Zawgyi customer's code points), then sells once and adds a customer
// so the Android side can pull them (r15_android_flow_test.dart QA_STEP=pullios).
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';

import 'qa_harness.dart';

const zawgyi = 'ေမာင္ေမာင္';
const unicode = 'မောင်မောင်';
String cps(String s) => s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ');

void main() {
  qaBinding();

  testWidgets('r15 iPhone = phone B of the Android shop: pull, check, sell, push', (tester) async {
    final app = await launchApp(tester);
    await wait(tester, const Duration(seconds: 2));
    await unlockIfLocked(tester, app);
    await signInIfSignedOut(tester, app, '9 790 917 151');
    note('status=${app.container.read(authControllerProvider).status} route=${app.router.location}');
    final db = app.db;
    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
        (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get()).map((r) => r.data).toList();
    // first sync may still be running: wait until the Android data is here
    final end = DateTime.now().add(const Duration(seconds: 60));
    while ((await q('SELECT COUNT(*) n FROM sales')).first['n'] as int < 150) {
      if (DateTime.now().isAfter(end)) break;
      await wait(tester, const Duration(seconds: 1));
    }
    await app.container.read(syncEngineProvider).syncNow(manual: true);
    await settle(tester);

    final counts = await q('SELECT (SELECT COUNT(*) FROM products) p, (SELECT COUNT(*) FROM sales) s, '
        '(SELECT COUNT(*) FROM sales WHERE voidedAt IS NOT NULL) voided, (SELECT COUNT(*) FROM customers) c, '
        '(SELECT COUNT(*) FROM productSerials) imeis, (SELECT COUNT(*) FROM productBatches) batches');
    note('iPhone after pull: ${counts.first}');
    for (final r in await q('SELECT name FROM customers')) {
      note('iPhone customer name=${r['name']} [${cps(r['name']! as String)}]');
    }
    for (final r in await q("SELECT name, (SELECT COALESCE(SUM(qtyMilli),0) FROM stockMovements m WHERE m.productId=p.id) stock "
        "FROM products p WHERE p.name LIKE 'QA r15%'")) {
      note('iPhone stock $r');
    }
    expect(counts.first['s'] as int, greaterThanOrEqualTo(150), reason: 'Android sales reached the iPhone');
    expect((await q('SELECT 1 FROM customers WHERE name = ?', [zawgyi])), isNotEmpty,
        reason: 'the Zawgyi name arrives byte for byte');

    app.router.go(Routes.customers);
    await settle(tester);
    await tapText(tester, 'အားလုံး');
    await shot(tester, 'r15_ios_customers_all');

    // iPhone sells 1 Soda (cash) and adds a customer
    app.router.go(Routes.pos);
    await settle(tester);
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
    await tapText(tester, 'QA r15 Soda');
    expect(app.container.read(cartProvider).lines.length, 1);
    await tapText(tester, 'ငွေရှင်းမယ်');
    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
    await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
    final s = await q('SELECT no, total, deviceId FROM sales ORDER BY createdAt DESC LIMIT 1');
    note('iPhone sale ${s.first}');
    app.router.push(Routes.addCustomer);
    await settle(tester);
    await type(tester, field('အမည်'), 'QA r15 iOS ဦးဘ');
    await type(tester, field('ဖုန်းနံပါတ်'), '09 790 011 153');
    await tapText(tester, 'သိမ်းမယ်', last: true);
    await wait(tester, const Duration(seconds: 2));
    await app.container.read(syncEngineProvider).syncNow(manual: true);
    await settle(tester);
    final outbox = await q('SELECT COUNT(*) n FROM outbox');
    note('iPhone pushed; outbox left=${outbox.first['n']}');
    expect(outbox.first['n'], 0);
    await shot(tester, 'r15_ios_after_push');
  });
}
