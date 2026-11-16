// QA round 15 (Android emulator, debug build, live API on the scratch DB via http://10.0.2.2:5076).
// Shop "QA r15 Android" was registered on the REAL app with adb (phone +959790917151, PIN 111111, phone-shop template).
// Run with run_qa_android.sh; QA_STEP selects the part:
//   data    → products with barcode / IMEI / batch (batch module switched on), two customers (one with a ZAWGYI name)
//   sales   → cash, debt and KBZPay sales; void the cash sale; reports; sync
//   zawgyi  → what the app stores / shows / finds for the Zawgyi name (TC-UX-NEW-16)
//   timing  → POS and Reports load times inside the app (debug build, see the note in the summary)
//   pullios → after the iPhone synced: pull, check what the iPhone sent (TC-SYNC two-way)
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/app_switch_tile.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'qa_harness.dart';
import 'package:zaypos_app/core/utils/myanmar.dart';
import 'package:zaypos_app/core/widgets/date_picker.dart';

const step = String.fromEnvironment('QA_STEP');
const zawgyi = 'ေမာင္ေမာင္'; // U+1031 before the consonant, U+1039 as asat (Zawgyi order)
const unicode = 'မောင်မောင်'; // the same name in Unicode
String cps(String s) => s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ');

Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

void main() {
  qaBinding();

  testWidgets('r15 Android: $step', (tester) async {
    final app = await launchApp(tester);
    await wait(tester, const Duration(seconds: 2));
    await unlockIfLocked(tester, app);
    await signInIfSignedOut(tester, app, '9 790 917 151');
    final db = app.db;
    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
        (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get()).map((r) => r.data).toList();
    Future<void> syncNow(String why) async {
      final t = DateTime.now();
      await app.container.read(syncEngineProvider).syncNow(manual: true);
      await settle(tester);
      final outbox = await q('SELECT COUNT(*) n FROM outbox');
      note('sync ($why) took ${DateTime.now().difference(t).inMilliseconds} ms; outbox rows left=${outbox.first['n']}');
    }

    // Phone shop: every new product starts with "တစ်လုံးချင်း IMEI … မှတ်မယ်" ON; switch it off for non-IMEI goods.
    Future<void> serialOff() async {
      final tile = find.byWidgetPredicate((w) => w is AppSwitchTile && w.title == 'တစ်လုံးချင်း IMEI / စီးရီးနံပါတ် မှတ်မယ်');
      if (tile.evaluate().isEmpty) return;
      final t = find.descendant(of: tile, matching: find.byType(AppSwitch));
      await tester.ensureVisible(t);
      await settle(tester);
      await tester.tap(t);
      await settle(tester);
      note('IMEI switch tapped; stockQty field now present=${keyed('stockQty').evaluate().isNotEmpty}');
    }

    Future<void> save() async {
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await settle(tester);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await wait(tester, const Duration(seconds: 2));
    }

    switch (step) {
      // ------------------------------------------------------------------------------------------ data
      case 'data':
        // Settings → ဆိုင် Features → "သက်တမ်း / Batch" switch: same call the switch makes.
        app.container.read(tenantFeaturesProvider.notifier).set(FeatureFlag.expiryBatch, true);
        await settle(tester);
        note(
          'features: serial=${app.container.read(tenantFeaturesProvider).serialWarranty} '
          'batch=${app.container.read(tenantFeaturesProvider).expiryBatch}',
        );

        Future<bool> has(String name) async => (await q('SELECT 1 FROM products WHERE name = ?', [name])).isNotEmpty;
        // 1. barcode product
        if (!await has('QA r15 Soda')) {
          app.router.push(Routes.addProduct);
          await settle(tester);
          await type(tester, keyed('productName'), 'QA r15 Soda');
          await type(tester, keyed('barcode'), '8850999150003');
          await type(tester, keyed('price'), '1500');
          await serialOff();
          if (keyed('stockQty').evaluate().isNotEmpty) await type(tester, keyed('stockQty'), '20');
          await shot(tester, 'r15_prod_barcode_form');
          await save();
          note('after save 1: route=${app.router.location}');
        }

        // 2. IMEI product (two IMEIs added with the keyboard's done key)
        if (!await has('QA r15 Phone')) {
          app.router.push(Routes.addProduct);
          await settle(tester);
          await type(tester, keyed('productName'), 'QA r15 Phone');
          await type(tester, keyed('price'), '450000');
          for (final imei in ['351500000000011', '351500000000012']) {
            await type(tester, keyed('imei'), imei);
            await tester.testTextInput.receiveAction(TextInputAction.done); // the keyboard's "done" adds it
            await settle(tester);
          }
          await shot(tester, 'r15_prod_imei_form');
          await save();
          note('after save 2: route=${app.router.location}');
        }

        // 3. batch product (Burmese name), ရက် ၃၀, batch B15, 10 pcs, expiry from the DATE PICKER (font check)
        app.router.push(Routes.addProduct);
        await settle(tester);
        await type(tester, keyed('productName'), 'QA r15 ဆေး');
        await type(tester, keyed('price'), '2000');
        await serialOff();
        await tester.ensureVisible(find.byKey(const ValueKey('expiryWarn')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('expiryWarn')));
        await settle(tester);
        await shot(tester, 'r15_prod_batch_expirywarn_menu');
        await tester.tap(find.text('ရက် ၃၀ အလို').last);
        await settle(tester);
        await type(tester, keyed('batchNo'), 'B15');
        await type(tester, keyed('stockQty'), '10');
        final exp = find.bySemanticsLabel('သက်တမ်းကုန်ရက်');
        await tester.ensureVisible(exp.last);
        await settle(tester);
        await tester.tap(exp.last);
        await settle(tester);
        await shot(tester, 'r15_prod_batch_date_picker');
        await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text(mmDigits(28))));
        await settle(tester);
        await tester.tap(find.text(datePickerConfirmText)); // BUG-54: Burmese picker
        await settle(tester);
        await shot(tester, 'r15_prod_batch_form');
        await save();
        note('after save 3: route=${app.router.location}');

        // customers
        Future<void> addCustomer(String name, String phone, String shotName) async {
          app.router.push(Routes.addCustomer);
          await settle(tester);
          await type(tester, field('အမည်'), name);
          await type(tester, field('ဖုန်းနံပါတ်'), phone);
          await shot(tester, shotName);
          await save();
          note('customer "$name" saved; route=${app.router.location}');
        }

        await addCustomer('QA r15 ဒေါ်လှ', '09 790 011 151', 'r15_cust_unicode_form');
        await addCustomer(zawgyi, '09 790 011 152', 'r15_cust_zawgyi_form');

        for (final r in await q(
          'SELECT p.name, p.barcode, (SELECT COUNT(*) FROM productSerials s WHERE s.productId=p.id) imeis, '
          "(SELECT GROUP_CONCAT(b.batchNo || '@' || b.expiryDate) FROM productBatches b WHERE b.productId=p.id) batches "
          "FROM products p WHERE p.name LIKE 'QA r15%'",
        )) {
          note('product $r');
        }
        for (final r in await q('SELECT name, phone FROM customers')) {
          note('customer name=${r['name']} [${cps(r['name']! as String)}] phone=${r['phone']}');
        }
        await syncNow('data');
        app.router.go(Routes.products);
        await settle(tester);
        await shot(tester, 'r15_products_list');

      // ------------------------------------------------------------------------------------------ sales
      case 'sales':
        Cart cart() => app.container.read(cartProvider);
        Future<void> openPosProducts() async {
          app.router.go(Routes.pos);
          await settle(tester);
          if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
        }

        Future<String> checkout(String method, {String? customer, required String shotName}) async {
          await tapText(tester, 'ငွေရှင်းမယ်');
          if (method != 'ငွေသား') await tapText(tester, method);
          if (customer != null) {
            await tapText(tester, 'ဖောက်သည် ရွေးပါ');
            await tapText(tester, customer, last: true);
          }
          await shot(tester, '${shotName}_checkout');
          await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
          await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
          await shot(tester, '${shotName}_done');
          final s = await q('SELECT id, no, method, total, customerId FROM sales ORDER BY createdAt DESC LIMIT 1');
          note('$shotName: sale ${s.first}');
          return s.first['id']! as String;
        }

        // cash: Coke × 2
        await openPosProducts();
        await tapText(tester, 'QA r15 Soda');
        await tapText(tester, 'QA r15 Soda');
        expect(cart().lines.single.qtyMilli, 2000);
        final cashId = await checkout('ငွေသား', shotName: 'r15_sale_cash');
        // debt: ဆေး × 1 (batch sheet if shown)
        await openPosProducts();
        await tapText(tester, 'QA r15 ဆေး');
        if (find.text('ဘယ် Batch လဲ?').evaluate().isNotEmpty) {
          await shot(tester, 'r15_pos_batch_sheet');
          await tapText(tester, 'B15', last: true);
        }
        await checkout('အကြွေး', customer: 'QA r15 ဒေါ်လှ', shotName: 'r15_sale_debt');
        // KBZPay: Phone, IMEI picked
        await openPosProducts();
        await tapText(tester, 'QA r15 Phone');
        await shot(tester, 'r15_pos_imei_sheet');
        await tapText(tester, '351500000000011', last: true);
        await checkout('KBZPay', shotName: 'r15_sale_kbz');
        // void the cash sale
        app.router.go(Routes.sale(cashId));
        await settle(tester);
        await tapText(tester, 'ပယ်ဖျက်မယ်');
        await wait(tester, const Duration(seconds: 1));
        await shot(tester, 'r15_sale_cash_voided');
        for (final r in await q('SELECT no, method, total, voidedAt FROM sales ORDER BY createdAt')) {
          note('sale $r');
        }
        for (final r in await q(
          'SELECT name, (SELECT COALESCE(SUM(qtyMilli),0) FROM stockMovements m WHERE m.productId=p.id) stock '
          "FROM products p WHERE p.name LIKE 'QA r15%'",
        )) {
          note('stock $r');
        }
        await syncNow('sales');
        app.router.go(Routes.reports);
        await settle(tester);
        await wait(tester, const Duration(seconds: 1));
        await shot(tester, 'r15_reports');

      // ------------------------------------------------------------------------------------------ zawgyi
      case 'zawgyi':
        for (final r in await q('SELECT name FROM customers')) {
          note('stored name=${r['name']} [${cps(r['name']! as String)}]');
        }
        app.router.go(Routes.customers);
        await settle(tester);
        await tapText(tester, 'အားလုံး');
        await shot(tester, 'r15_zg_customers_all');
        for (final (label, query) in [('unicode', unicode), ('zawgyi', zawgyi), ('unicode_part', 'မောင်'), ('phone', '011152')]) {
          await type(tester, find.byType(EditableText), query);
          await wait(tester, const Duration(milliseconds: 600));
          final hit = find.textContaining(zawgyi).evaluate().length + find.textContaining(unicode).evaluate().length;
          // the search field itself also contains the query: subtract it
          final inField = (query.contains(zawgyi) || query.contains(unicode)) ? 1 : 0;
          note('search $label "$query" [${cps(query)}]: rows showing the name=${hit - inField}');
          await shot(tester, 'r15_zg_search_$label');
        }
        await type(tester, find.byType(EditableText), '');

      // ------------------------------------------------------------------------------------------ seed (for timing)
      // 150 sales through the app's own cart + checkout service (quick-sale lines, cash / KBZPay alternating), then sync.
      case 'seed':
        final cartN = app.container.read(cartProvider.notifier);
        final svc = app.container.read(checkoutServiceProvider);
        final sw = Stopwatch()..start();
        for (var i = 0; i < 150; i++) {
          cartN.addQuick(1000 + (i % 7) * 500, 'QA r15 seed ${i % 10}');
          cartN.addQuick(2500, 'QA r15 seed b');
          await svc.checkout(CheckoutRequest(
              lines: app.container.read(cartProvider).toDrafts(),
              method: i.isEven ? PaymentMethod.cash : PaymentMethod.kbz));
          cartN.clear();
          if (i % 25 == 0) await tester.pump();
        }
        note('seeded 150 sales in ${sw.elapsedMilliseconds} ms');
        await syncNow('seed');

      // ------------------------------------------------------------------------------------------ timing
      case 'timing':
        final counts = await q(
          'SELECT (SELECT COUNT(*) FROM products) p, (SELECT COUNT(*) FROM sales) s, '
          '(SELECT COUNT(*) FROM customers) c',
        );
        note('data: ${counts.first}');
        Future<int> measure(String route, Finder ready) async {
          app.router.go(Routes.dashboard);
          await settle(tester);
          final sw = Stopwatch()..start();
          app.router.go(route);
          while (ready.evaluate().isEmpty) {
            await tester.pump(const Duration(milliseconds: 5));
            if (sw.elapsed > const Duration(seconds: 20)) fail('$route did not load');
          }
          return sw.elapsedMilliseconds;
        }

        for (var i = 0; i < 4; i++) {
          final pos = await measure(Routes.pos, find.text('ငွေရှင်းမယ်'));
          final rpt = await measure(Routes.reports, find.text('နောက်ဆုံး ၇ ရက်'));
          note('timing run ${i + 1} (${i == 0 ? 'first open after launch' : 'warm'}): POS $pos ms, Reports $rpt ms');
        }

      // ------------------------------------------------------------------------------------------ pullios
      case 'pullios':
        await syncNow('pull from iPhone');
        for (final r in await q('SELECT no, method, total, voidedAt, deviceId FROM sales ORDER BY createdAt')) {
          note('sale $r');
        }
        for (final r in await q('SELECT name, phone FROM customers')) {
          note('customer name=${r['name']} [${cps(r['name']! as String)}]');
        }
        for (final r in await q(
          'SELECT name, (SELECT COALESCE(SUM(qtyMilli),0) FROM stockMovements m WHERE m.productId=p.id) stock '
          'FROM products p',
        )) {
          note('stock $r');
        }
        app.router.go(Routes.sales);
        await settle(tester);
        await shot(tester, 'r15_android_sales_after_ios');
        app.router.go(Routes.customers);
        await settle(tester);
        await tapText(tester, 'အားလုံး');
        await shot(tester, 'r15_android_customers_after_ios');

      default:
        fail('QA_STEP missing');
    }
    note('done $step');
  });
}
