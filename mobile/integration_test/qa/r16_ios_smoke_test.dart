// QA round 16: short iOS smoke. The iPhone simulator is the SECOND phone of the Android shop "QA r16 Android"
// (+95979091716, PIN 111111). Run with run_qa.sh (iOS runner, API on localhost:5076, scratch DB).
// Signs in, pulls what the Android emulator made (incl. the Zawgyi-typed customer, now Unicode), sells once (cash),
// shows the receipt and opens the share sheet ("ပြေစာ ပို့မယ်"), then pushes so the Android side can pull (QA_STEP=pull).
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';

import 'qa_harness.dart';

String cps(String s) => s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ');

void main() {
  qaBinding();

  testWidgets('r16 iPhone = phone B of the Android shop: pull, sell, receipt + share sheet, push', (tester) async {
    final app = await launchApp(tester);
    await wait(tester, const Duration(seconds: 2));
    await unlockIfLocked(tester, app);
    await signInIfSignedOut(tester, app, '9 7909 1716');
    final db = app.db;
    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
        (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get()).map((r) => r.data).toList();
    final end = DateTime.now().add(const Duration(seconds: 60));
    while ((await q('SELECT COUNT(*) n FROM sales')).first['n'] as int < 2) {
      if (DateTime.now().isAfter(end)) break;
      await wait(tester, const Duration(seconds: 1));
    }
    await app.container.read(syncEngineProvider).syncNow(manual: true);
    await settle(tester);
    final counts = await q('SELECT (SELECT COUNT(*) FROM products) p, (SELECT COUNT(*) FROM sales) s, '
        '(SELECT COUNT(*) FROM customers) c');
    note('iPhone after pull: ${counts.first}');
    for (final r in await q('SELECT name, phone FROM customers ORDER BY phone')) {
      note('iPhone customer ${r['phone']} name=${r['name']} [${cps(r['name']! as String)}]');
    }
    expect(counts.first['s'] as int, greaterThanOrEqualTo(2), reason: 'the Android sales reached the iPhone');
    expect(await q('SELECT 1 FROM customers WHERE name = ?', ['မောင်မောင်']), isNotEmpty,
        reason: 'the Zawgyi-typed customer arrives in Unicode');

    app.router.go(Routes.pos);
    await settle(tester);
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
    await tapText(tester, 'QA r16 WithCost');
    expect(app.container.read(cartProvider).lines.length, 1);
    await tapText(tester, 'ငွေရှင်းမယ်');
    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
    await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
    final s = await q('SELECT no, total, method FROM sales ORDER BY createdAt DESC LIMIT 1');
    note('iPhone sale ${s.first}');
    await shot(tester, 'r16_ios_receipt');
    await app.container.read(syncEngineProvider).syncNow(manual: true);
    await settle(tester);
    final outbox = await q('SELECT COUNT(*) n FROM outbox');
    note('iPhone pushed; outbox left=${outbox.first['n']}');
    expect(outbox.first['n'], 0);

    await tapText(tester, receiptShareText);
    await wait(tester, const Duration(seconds: 4));
    await shot(tester, 'r16_ios_receipt_share_sheet');
  });
}
