// QA round 12b — TC-SYNC-NEW-28 on two simulators (QA_ROLE=A on iPhone 17, QA_ROLE=B on iPhone 17e, run at the same time).
// Sell 1 on A and sync both. A goes "offline" (the API is stopped instead of airplane mode) → void the sale → wait
// 2–3 minutes. The API comes back; B voids the same sale and syncs. A is "back online": its stock is watched for a few
// minutes (1 too many is the accepted Known limitation), then "ယခု sync လုပ်မယ်" → the stock is right and the sale is
// voided on both phones.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'qa_harness.dart';

const role = String.fromEnvironment('QA_ROLE');
const soap = 'QA r12b ဆပ်ပြာ';

void main() {
  qaBinding();

  testWidgets('TC-SYNC-NEW-28 two phones void one sale ($role)', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    await signInIfSignedOut(tester, app, '9 790 917 051', pin: '222222');

    // Keep both streams subscribed so reads are current even when their screens are closed.
    app.container.listen(productsProvider, (_, _) {});
    app.container.listen(salesProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 1));

    double stock() {
      final p = (app.container.read(productsProvider).value ?? const []).where((v) => v.product.name == soap).single;
      return p.stockMilli / 1000;
    }

    List<Sale> sales() => app.container.read(salesProvider).value ?? const [];
    Sale? byId(String id) => sales().where((s) => s.id == id).firstOrNull;

    if (role == 'A') {
      await syncNowViaUi(tester, app);
      final s0 = stock();
      final knownIds = sales().map((s) => s.id).toSet();
      // Sell 1 on the POS screen (tap the product tile, checkout).
      app.router.go(Routes.pos);
      await settle(tester);
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
      await tapText(tester, soap);
      await tapText(tester, 'ငွေရှင်းမယ်');
      await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
      await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
      await wait(tester, const Duration(seconds: 1));
      final sale = sales().where((s) => !knownIds.contains(s.id)).single;
      await syncNowViaUi(tester, app);
      final s1 = stock();
      note('A: stock before $s0, after selling 1 and syncing $s1; sale #${sale.no} pending=${sale.pending}');
      raiseFlag('A_sold', sale.id);

      await awaitFlag(tester, 'B_synced');
      await hostCmd(tester, 'api_stop');
      app.router.go(Routes.sale(sale.id));
      await settle(tester);
      await tapText(tester, 'ပယ်ဖျက်မယ်');
      await wait(tester, const Duration(seconds: 2));
      note('A offline: voided; stock ${stock()} (expected ${s1 + 1})');
      await shot(tester, 'sync28_A_voided_offline');
      await wait(tester, const Duration(minutes: 2, seconds: 30));
      app.router.go(Routes.dashboard);
      await settle(tester);
      note('A offline after 2.5 min: stock ${stock()}');
      await shot(tester, 'sync28_A_offline_after_wait');
      raiseFlag('A_voided_offline');

      await awaitFlag(tester, 'B_voided');
      // "Airplane mode OFF": the API is up again (B started it). Watch A's stock without touching anything.
      final seen = <String>[];
      for (var i = 0; i <= 8; i++) {
        seen.add('+${i * 30}s ${stock()}');
        if (i == 2) await shot(tester, 'sync28_A_back_online_1min');
        if (i < 8) await wait(tester, const Duration(seconds: 30));
      }
      note('A back online, stock every 30 s (no manual sync): $seen');
      app.router.go(Routes.products);
      await settle(tester);
      await shot(tester, 'sync28_A_back_online_4min_products');
      await syncNowViaUi(tester, app);
      await wait(tester, const Duration(seconds: 3));
      final after = byId(sale.id);
      note('A after "ယခု sync လုပ်မယ်": stock ${stock()} (right = $s0), sale voided=${after?.voided}');
      await shot(tester, 'sync28_A_after_manual_sync');
      app.router.go(Routes.sale(sale.id));
      await settle(tester);
      await shot(tester, 'sync28_A_sale_detail_final');
      raiseFlag('A_done', '${stock()}');
      expect(stock(), s0, reason: 'after a manual sync the stock is right');
      expect(after?.voided, isTrue);
    } else {
      final saleId = await awaitFlag(tester, 'A_sold');
      final end = DateTime.now().add(const Duration(minutes: 2));
      while (byId(saleId) == null && DateTime.now().isBefore(end)) {
        await syncNowViaUi(tester, app);
      }
      note('B: has the sale=${byId(saleId) != null}, stock ${stock()}');
      final s1 = stock();
      raiseFlag('B_synced');

      await awaitFlag(tester, 'A_voided_offline');
      await hostCmd(tester, 'api_start');
      app.router.go(Routes.sale(saleId));
      await settle(tester);
      await tapText(tester, 'ပယ်ဖျက်မယ်');
      await wait(tester, const Duration(seconds: 1));
      await syncNowViaUi(tester, app);
      note('B voided + synced: stock ${stock()} (expected ${s1 + 1}), voided=${byId(saleId)?.voided}');
      await shot(tester, 'sync28_B_voided_synced');
      raiseFlag('B_voided');

      await awaitFlag(tester, 'A_done');
      await syncNowViaUi(tester, app);
      note('B final: stock ${stock()}, voided=${byId(saleId)?.voided}');
      app.router.go(Routes.products);
      await settle(tester);
      await shot(tester, 'sync28_B_final_products');
      expect(byId(saleId)?.voided, isTrue);
    }
  });
}
