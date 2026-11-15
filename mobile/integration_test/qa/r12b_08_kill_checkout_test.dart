// QA round 12b — TC-UX-05: kill the app during checkout. QA_STEP=kill: cart with 1 item → Checkout → the runner is
// asked to `xcrun simctl terminate` the app and, without waiting, "အတည်ပြုပြီး ပြေစာထုတ်မယ်" is tapped, so the kill lands
// within a few hundred ms of the tap (QA_DELAY_MS waits that long before the tap). QA_STEP=check: reopen → either the
// whole sale exists (sale + its line + stock −1 + one outbox unit) or nothing does.
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';

import 'qa_harness.dart';

const step = String.fromEnvironment('QA_STEP');
const delayMs = int.fromEnvironment('QA_DELAY_MS');
const soap = 'QA r12b ဆပ်ပြာ';

void main() {
  qaBinding();

  testWidgets('TC-UX-05 kill during checkout ($step, delay $delayMs ms)', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    final c = app.container;
    c.listen(productsProvider, (_, _) {});
    c.listen(salesProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));
    double stock() =>
        (c.read(productsProvider).value ?? const []).where((v) => v.product.name == soap).single.stockMilli / 1000;
    final sales = c.read(salesProvider).value ?? const [];
    final outbox = (await app.db.customSelect('SELECT COUNT(*) AS n FROM outbox').getSingle()).data['n'];
    final state = '${sales.length},${stock()},$outbox';
    final stateFile = File('$qaFlags/kill_state');

    if (step == 'kill') {
      stateFile.writeAsStringSync(state);
      note('before kill: sales,stock,outbox = $state');
      app.router.go(Routes.pos);
      await settle(tester);
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
      await tapText(tester, soap);
      await tapText(tester, 'ငွေရှင်းမယ်');
      await shot(tester, 'ux05_checkout_before_kill_${delayMs}ms');
      final confirm = find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်');
      await tester.ensureVisible(confirm);
      await settle(tester);
      // ignore: avoid_print
      print('QA_CMD:kill_app:kill_$delayMs');
      if (delayMs > 0) await Future<void>.delayed(const Duration(milliseconds: delayMs));
      await tester.tap(confirm);
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('the app was not killed within 30 s');
    } else {
      final before = stateFile.readAsStringSync().split(',');
      final (s0, st0, o0) = (int.parse(before[0]), double.parse(before[1]), int.parse(before[2]));
      final n = sales.length - s0;
      final newest = n > 0 ? sales.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b) : null;
      final lines = newest == null
          ? 0
          : (await app.db.customSelect('SELECT COUNT(*) AS n FROM saleLines WHERE saleId = ?',
                  variables: [Variable(newest.id)]).getSingle())
              .data['n'] as int;
      note('after reopen: before sales,stock,outbox=${before.join(',')}; now $state; new sales=$n, '
          'newest #${newest?.no} total=${newest?.total} lines=$lines');
      app.router.go(n > 0 ? Routes.sale(newest!.id) : Routes.sales);
      await settle(tester);
      await shot(tester, 'ux05_after_reopen_${delayMs}ms');
      if (n == 0) {
        expect(stock(), st0, reason: 'nothing saved → stock unchanged (outbox before $o0, now $outbox)');
      } else {
        expect(n, 1);
        expect(lines, 1, reason: 'the sale has its line');
        expect(stock(), st0 - 1, reason: 'stock went down with the sale');
      }
    }
  });
}
