// QA round 12b — TC-UX-06 on a simulator: QA_MINUTES of "normal use" in a loop on phone A (sell on POS, open the receipt,
// Dashboard, Reports, Sales, Customers + search, Products, manual sync). Every error the framework reports is collected;
// the host logs the app's memory (RSS) every 5 minutes ("[runner] app RSS …" in the log).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';

import 'qa_harness.dart';

const minutes = int.fromEnvironment('QA_MINUTES', defaultValue: 60);
const soap = 'QA r12b ဆပ်ပြာ';

void main() {
  qaBinding();

  testWidgets('TC-UX-06 $minutes minutes of normal use', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    final c = app.container;
    c.listen(productsProvider, (_, _) {});
    c.listen(salesProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));
    double stock() =>
        (c.read(productsProvider).value ?? const []).where((v) => v.product.name == soap).single.stockMilli / 1000;

    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => problems.add('${d.exceptionAsString().split('\n').first} @ ${app.router.location}');

    // Setup, not under test: 100 more soap so a sale fits in every loop of the hour.
    final soapId = (c.read(productsProvider).value ?? const []).where((v) => v.product.name == soap).single.product.id;
    await c.read(stockServiceProvider).restock(productId: soapId, qtyMilli: 100000, note: 'QA r12b soak');
    await wait(tester, const Duration(seconds: 1));
    final end = DateTime.now().add(const Duration(minutes: minutes));
    var nextMem = DateTime.now();
    var loops = 0, sold = 0;
    final salesAtStart = (c.read(salesProvider).value ?? const []).length;
    final stockAtStart = stock();
    await hostCmd(tester, 'mem');
    while (DateTime.now().isBefore(end)) {
      loops++;
      if (stock() >= 1) {
        app.router.go(Routes.pos);
        await settle(tester);
        if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
        await tapText(tester, soap);
        await tapText(tester, 'ငွေရှင်းမယ်');
        await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
        await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
        sold++;
      }
      for (final r in [Routes.dashboard, Routes.reports, Routes.sales, Routes.customers, Routes.products]) {
        app.router.go(r);
        await settle(tester);
        await wait(tester, const Duration(seconds: 2));
      }
      app.router.go(Routes.customers);
      await settle(tester);
      await tapText(tester, 'အားလုံး');
      await type(tester, find.byType(EditableText), '790');
      await wait(tester, const Duration(seconds: 1));
      if (loops % 3 == 0) await syncNowViaUi(tester, app);
      if (DateTime.now().isAfter(nextMem)) {
        await hostCmd(tester, 'mem');
        await shot(tester, 'ux06_soak_${loops.toString().padLeft(3, '0')}');
        nextMem = DateTime.now().add(const Duration(minutes: 5));
      }
      await wait(tester, const Duration(seconds: 20)); // a cashier is not a robot
    }
    await syncNowViaUi(tester, app);
    await hostCmd(tester, 'mem');
    final salesNow = (c.read(salesProvider).value ?? const []).length;
    note('soak: $loops loops in $minutes min, $sold sales (sales $salesAtStart → $salesNow, '
        'stock $stockAtStart → ${stock()}), problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    await shot(tester, 'ux06_soak_end');
    FlutterError.onError = old;
    expect(salesNow - salesAtStart, sold);
    expect(problems, isEmpty);
  });
}
