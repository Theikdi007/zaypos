// QA round 16 (targeted re-test of the round-15 fixes, fix/android @ 3c9e102), Android emulator, debug build,
// live API on the scratch DB (http://10.0.2.2:5076). Shop "QA r16 Android" (+95979091716, PIN 111111, pharmacy
// template) was registered on the REAL app with adb (BUG-51 check). Run with run_qa_android.sh; QA_STEP:
//   products → BUG-53: cost / price empty with "ဥပမာ …" hints (pharmacy, grocery, phone); name only / price only /
//              price + cost saved; "အရင်းမသိ" in the list
//   sales    → BUG-53: sell (no cost + with cost) → dashboard and Reports profit = the known line only + the note;
//              then the name-only product → POS asks for the price
//   zawgyi   → BUG-52: Zawgyi customer name / address / note and product name typed → stored as Unicode, found by
//              Unicode and Zawgyi search; valid Unicode left alone
//   pull     → after the iPhone synced: pull and list what arrived (two-way smoke)
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/widgets/app_switch_tile.dart';
import 'package:zaypos_app/features/customers/presentation/widgets/customer_row.dart';

import 'package:zaypos_app/core/utils/myanmar.dart';

import 'qa_harness.dart';

const step = String.fromEnvironment('QA_STEP');
String cps(String s) => s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ');
Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

// Zawgyi input (as a Zawgyi keyboard commits it) → the Unicode spelling QA expects, written independently.
const zgName = 'ေမာင္ေမာင္'; // U+1031 U+1019 U+102C U+1004 U+1039 ×2
const uniName = 'မောင်မောင်'; // U+1019 U+1031 U+102C U+1004 U+103A ×2
const zgAddress = 'ရန္ကုန္'; // asat typed as U+1039
const uniAddress = 'ရန်ကုန်';
const zgNote = 'ေၾကြးက်န္'; // ေ + ၾ (U+107E) + က + ြ(wa in Zawgyi) + း , က + ်(ya in Zawgyi) + န + ္
const uniNote = 'ကြွေးကျန်';
const zgProduct = 'ေဆးလံုး'; // ေ first, ံ before ု
const uniProduct = 'ဆေးလုံး';
// Valid Unicode that must NOT change (the detector alone scores the first one as Zawgyi, see myanmar_text.dart).
const uniKeep1 = 'ယခု မိုးရွာနေပါသလား';
const uniKeep2 = 'ကျွန်ုပ်';

void main() {
  qaBinding();

  testWidgets('r16 Android: $step', (tester) async {
    final app = await launchApp(tester);
    await wait(tester, const Duration(seconds: 2));
    await unlockIfLocked(tester, app);
    await signInIfSignedOut(tester, app, '9 7909 1716');
    final db = app.db;
    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
        (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get()).map((r) => r.data).toList();
    Future<void> syncNow(String why) async {
      await app.container.read(syncEngineProvider).syncNow(manual: true);
      await settle(tester);
      final outbox = await q('SELECT COUNT(*) n FROM outbox');
      note('sync ($why): outbox rows left=${outbox.first['n']}');
    }

    Future<void> save() async {
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await settle(tester);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await wait(tester, const Duration(seconds: 2));
    }

    Future<void> serialOff() async {
      final tile = find.byWidgetPredicate((w) => w is AppSwitchTile && w.title.contains('IMEI'));
      if (tile.evaluate().isEmpty) return;
      final t = find.descendant(of: tile, matching: find.byType(AppSwitch));
      await tester.ensureVisible(t);
      await settle(tester);
      await tester.tap(t);
      await settle(tester);
    }

    Future<Map<String, Object?>?> product(String name) async =>
        (await q('SELECT id, name, price, cost FROM products WHERE name = ?', [name])).firstOrNull;

    final failures = <String>[];
    void check(bool ok, String what) {
      note('${ok ? 'OK  ' : 'FAIL'} $what');
      if (!ok) failures.add(what);
    }

    switch (step) {
      // ------------------------------------------------------------------------------------------ products (BUG-53)
      case 'products':
        Future<void> formCheck(String tpl) async {
          app.router.push(Routes.addProduct);
          await settle(tester);
          final t = app.container.read(shopTemplateProvider);
          final cost = fieldText(tester, keyed('cost')), price = fieldText(tester, keyed('price'));
          check(cost.isEmpty && price.isEmpty, '$tpl form: cost="$cost" price="$price" (both must be empty)');
          final hc = find.text('ဥပမာ ${t.sampleCost}').evaluate().length;
          final hp = find.text('ဥပမာ ${t.samplePrice}').evaluate().length;
          check(hc == 1 && hp == 1, '$tpl form: hint "ဥပမာ ${t.sampleCost}" x$hc, "ဥပမာ ${t.samplePrice}" x$hp');
          await shot(tester, 'r16_bug53_${tpl}_form_empty');
        }

        Future<void> add(String name, {String? price, String? cost}) async {
          if (await product(name) != null) return;
          await type(tester, keyed('productName'), name);
          if (price != null) await type(tester, keyed('price'), price);
          if (cost != null) await type(tester, keyed('cost'), cost);
          await serialOff();
          if (cost == null) await shot(tester, 'r16_bug53_form_${name.replaceAll(' ', '_')}');
          await save();
          final p = await product(name);
          note('saved $name → $p (route ${app.router.location})');
        }

        note('template=${app.container.read(shopTemplateProvider).id}');
        await formCheck('pharmacy');
        await add('QA r16 NameOnly');
        check((await product('QA r16 NameOnly'))?['price'] == 0 && (await product('QA r16 NameOnly'))?['cost'] == 0,
            'name only → price 0, cost 0 (not 1500 / 1200)');
        app.router.push(Routes.addProduct);
        await settle(tester);
        await add('QA r16 NoCost', price: '1000');
        check((await product('QA r16 NoCost'))?['cost'] == 0, 'price only → cost 0 = unknown (not 1200)');
        app.router.push(Routes.addProduct);
        await settle(tester);
        await add('QA r16 WithCost', price: '1000', cost: '700');
        check((await product('QA r16 WithCost'))?['cost'] == 700, 'price + cost → cost 700');

        // Second and third template: the same call the register wizard makes (step 2), then back to pharmacy.
        final featuresBefore = app.container.read(tenantFeaturesProvider);
        for (final tpl in ['grocery', 'phone']) {
          app.container.read(shopTemplateProvider.notifier).select(tpl);
          await settle(tester);
          await formCheck(tpl);
          if (tpl == 'grocery') {
            await add('QA r16 Grocery NoCost', price: '500');
            check((await product('QA r16 Grocery NoCost'))?['cost'] == 0, 'grocery price only → cost 0 (not 450)');
          } else {
            app.router.go(Routes.products);
            await settle(tester);
          }
        }
        app.container.read(shopTemplateProvider.notifier).select('pharmacy');
        await settle(tester);
        note('features before=$featuresBefore after=${app.container.read(tenantFeaturesProvider)}');

        app.router.go(Routes.products);
        await settle(tester);
        await shot(tester, 'r16_bug53_products_list');
        final unknownRows = find.textContaining('အရင်းမသိ · ရောင်းဈေး').evaluate().length;
        final knownRow = find.textContaining('ဝယ်ဈေး 700 · ရောင်းဈေး 1,000').evaluate().length;
        // The name-only product (price 0) shows "ဈေးနှုန်း ထည့်ရန်" instead (first r16 run expected 3: QA's mistake; the
        // case is "save with price only → the row shows အရင်းမသိ").
        final needsPrice = find.text('ဈေးနှုန်း ထည့်ရန်').evaluate().length;
        check(unknownRows == 2 && knownRow == 1 && needsPrice == 1,
            'list: "အရင်းမသိ" rows=$unknownRows (2 price-only), cost row=$knownRow, "ဈေးနှုန်း ထည့်ရန်"=$needsPrice');
        await syncNow('products');

      // ------------------------------------------------------------------------------------------ sales (BUG-53)
      case 'sales':
        Future<void> openPos() async {
          app.router.go(Routes.pos);
          await settle(tester);
          if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
        }

        Future<void> checkoutCash(String shotName) async {
          await tapText(tester, 'ငွေရှင်းမယ်');
          await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
          await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
          await shot(tester, shotName);
        }

        Future<void> profitScreens(String tag, String profit, String note1) async {
          app.router.go(Routes.dashboard);
          await settle(tester);
          await wait(tester, const Duration(seconds: 1));
          await shot(tester, 'r16_bug53_dashboard_$tag');
          check(find.text(profit).evaluate().isNotEmpty, 'dashboard ($tag): profit "$profit"');
          check(find.text(note1).evaluate().length == 1, 'dashboard ($tag): note "$note1"');
          app.router.go(Routes.reports);
          await settle(tester);
          await wait(tester, const Duration(seconds: 1));
          await shot(tester, 'r16_bug53_reports_$tag');
          check(find.text(profit).evaluate().isNotEmpty, 'Reports ($tag): profit "$profit"');
          check(find.text(note1).evaluate().length == 1, 'Reports ($tag): note "$note1"');
        }

        if ((await q('SELECT COUNT(*) n FROM sales')).first['n'] == 0) {
          await openPos();
          await tapText(tester, 'QA r16 NoCost');
          await tapText(tester, 'QA r16 WithCost');
          await checkoutCash('r16_bug53_sale1_done');
        }
        for (final r in await q('SELECT l.name, l.price, l.costSnapshot, l.qtyMilli FROM saleLines l')) {
          note('line $r');
        }
        await profitScreens('sale1', '300 Ks', 'အရင်းမသိ 1 ခု မပါ');

        // name-only product: POS must ask for the price at the first sale
        await openPos();
        await tapText(tester, 'QA r16 NameOnly');
        final asked = find.text('ဈေးနှုန်း ထည့်ပါ').evaluate().isNotEmpty;
        await shot(tester, 'r16_bug53_pos_asks_price');
        check(asked, 'POS asks "ဈေးနှုန်း ထည့်ပါ" for the name-only product');
        if (asked) {
          for (final d in ['8', '0', '0']) {
            await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(d)).last);
            await settle(tester);
          }
          await tapText(tester, 'သိမ်းပြီး ခြင်းထဲထည့်မယ်');
          await checkoutCash('r16_bug53_sale2_done');
          check((await product('QA r16 NameOnly'))?['price'] == 800, 'name-only product price is now 800');
          await profitScreens('sale2', '300 Ks', 'အရင်းမသိ 2 ခု မပါ');
        }
        await syncNow('sales');

      // ------------------------------------------------------------------------------------------ zawgyi (BUG-52)
      case 'zawgyi':
        Future<void> addCustomer(String name, String phone, {String? address, String? noteText}) async {
          if ((await q('SELECT 1 FROM customers WHERE phone = ?', [phone])).isNotEmpty) return;
          app.router.push(Routes.addCustomer);
          await settle(tester);
          await type(tester, field('အမည်'), name);
          await type(tester, field('ဖုန်းနံပါတ်'), phone);
          if (address != null) await type(tester, field('လိပ်စာ'), address);
          if (noteText != null) await type(tester, field('မှတ်ချက်'), noteText);
          await shot(tester, 'r16_bug52_customer_form_$phone');
          await save();
        }

        await addCustomer(zgName, '09790917101', address: zgAddress, noteText: zgNote);
        await addCustomer(uniKeep1, '09790917102');
        await addCustomer(uniKeep2, '09790917103');
        if ((await q("SELECT 1 FROM products WHERE price = 500 AND name NOT LIKE 'QA%'")).isEmpty) {
          app.router.push(Routes.addProduct);
          await settle(tester);
          await type(tester, keyed('productName'), zgProduct);
          await type(tester, keyed('price'), '500');
          await type(tester, keyed('cost'), '300');
          await shot(tester, 'r16_bug52_product_form');
          await save();
        }

        final rows = await q('SELECT phone, name, address, note FROM customers ORDER BY phone');
        for (final r in rows) {
          note('customer ${r['phone']}: name=${r['name']} [${cps(r['name']! as String)}] '
              'address=${r['address']} [${cps((r['address'] ?? '') as String)}] note=${r['note']} [${cps((r['note'] ?? '') as String)}]');
        }
        final zg = rows.firstWhere((r) => r['phone'] == '09790917101');
        check(zg['name'] == uniName, 'Zawgyi name stored as Unicode ${cps(uniName)}');
        check(zg['address'] == uniAddress, 'Zawgyi address stored as Unicode ${cps(uniAddress)}');
        check(zg['note'] == uniNote, 'Zawgyi note stored as Unicode ${cps(uniNote)}');
        check(rows.firstWhere((r) => r['phone'] == '09790917102')['name'] == uniKeep1, 'valid Unicode "$uniKeep1" unchanged');
        check(rows.firstWhere((r) => r['phone'] == '09790917103')['name'] == uniKeep2, 'valid Unicode "$uniKeep2" unchanged');
        final prods = await q("SELECT name FROM products WHERE price = 500 AND name NOT LIKE 'QA%'");
        for (final p in prods) {
          note('product name=${p['name']} [${cps(p['name']! as String)}]');
        }
        check(prods.length == 1 && prods.first['name'] == uniProduct, 'Zawgyi product stored as Unicode ${cps(uniProduct)}');

        // customer search (UI): the "အားလုံး" chip is scrolled into view before the tap
        app.router.go(Routes.customers);
        await settle(tester);
        final all = find.text('အားလုံး');
        await tester.ensureVisible(all.first);
        await settle(tester);
        await tester.tap(all.first);
        await settle(tester);
        check(find.byType(CustomerRow).evaluate().length == 3, 'customers "အားလုံး": 3 rows, got ${find.byType(CustomerRow).evaluate().length}');
        await shot(tester, 'r16_bug52_customers_all');
        final search = find.byType(EditableText).first;
        for (final (label, query) in [('unicode', uniName), ('zawgyi', zgName), ('unicode_part', 'မောင်'), ('zawgyi_part', 'ေမာင္')]) {
          await type(tester, search, query);
          await wait(tester, const Duration(milliseconds: 600));
          final hits = find.byType(CustomerRow);
          final shown = find.descendant(of: hits, matching: find.text(uniName)).evaluate().length;
          check(hits.evaluate().length == 1 && shown == 1,
              'customer search $label "$query": rows=${hits.evaluate().length}, row shows Unicode name=$shown');
          await shot(tester, 'r16_bug52_cust_search_$label');
        }
        await type(tester, search, '');

        // product search (UI)
        app.router.go(Routes.products);
        await settle(tester);
        for (final (label, query) in [('unicode', uniProduct), ('zawgyi', zgProduct)]) {
          await type(tester, find.byType(EditableText).first, query);
          await wait(tester, const Duration(milliseconds: 600));
          final titles = find.byWidgetPredicate((w) => w is Text && w.data == uniProduct).evaluate().length;
          final others = find.textContaining('QA r16').evaluate().length;
          check(titles == 1 && others == 0, 'product search $label "$query": rows titled "$uniProduct"=$titles, others=$others');
          await shot(tester, 'r16_bug52_prod_search_$label');
        }
        await type(tester, find.byType(EditableText).first, '');
        await syncNow('zawgyi');

      // ------------------------------------------------------------------------------------------ pickers (BUG-54)
      // Every expiry date picker: Add Product, "Stock ဖြည့်မယ်" (new batch) and the edit form ("Batch အသစ်"), calendar
      // AND the keyboard-entry mode (pencil icon). TC-UX-02: no English except brand / payment names.
      case 'pickers':
        Future<void> inspect(String tag, {required bool choose}) async {
          await waitFor(tester, find.byType(DatePickerDialog), why: 'picker $tag');
          List<String> texts() => [
                for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Dialog), matching: find.byType(Text))))
                  t.data ?? t.textSpan?.toPlainText() ?? '',
                for (final e in tester.widgetList<InputDecorator>(
                    find.descendant(of: find.byType(Dialog), matching: find.byType(InputDecorator)))) ...[
                  e.decoration.hintText ?? '',
                  e.decoration.labelText ?? '',
                  e.decoration.errorText ?? '',
                ],
              ];
          final cal = texts();
          await shot(tester, 'r16_bug54_${tag}_calendar');
          final en1 = cal.where((t) => t.contains(RegExp('[A-Za-z]{2,}'))).toList();
          check(en1.isEmpty && cal.contains('ရွေးမယ်') && cal.contains('မလုပ်တော့'), '$tag calendar: English=$en1; texts=$cal');
          final pencil = find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.edit_outlined));
          if (pencil.evaluate().isNotEmpty) {
            await tester.tap(pencil);
            await settle(tester);
            final inp = texts();
            await shot(tester, 'r16_bug54_${tag}_input_mode');
            final en2 = inp.where((t) => t.contains(RegExp('[A-Za-z]{2,}'))).toList();
            check(en2.isEmpty, '$tag keyboard-entry mode: English=$en2; texts=$inp');
            await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.calendar_today)));
            await settle(tester);
          } else {
            note('$tag: no pencil (input mode) icon in the picker');
          }
          if (choose) {
            await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text(mmDigits(28))));
            await settle(tester);
            await tester.tap(find.text('ရွေးမယ်'));
          } else {
            await tester.tap(find.text('မလုပ်တော့'));
          }
          await settle(tester);
        }

        // 1. Add Product
        if (await product('QA r16 Batch') == null) {
          app.router.push(Routes.addProduct);
          await settle(tester);
          await type(tester, keyed('productName'), 'QA r16 Batch');
          await type(tester, keyed('price'), '2000');
          await type(tester, keyed('cost'), '1500');
          await tester.ensureVisible(find.byKey(const ValueKey('expiryWarn')));
          await settle(tester);
          await tester.tap(find.byKey(const ValueKey('expiryWarn')));
          await settle(tester);
          await tester.tap(find.text('ရက် ၃၀ အလို').last);
          await settle(tester);
          await type(tester, keyed('batchNo'), 'B16');
          if (keyed('stockQty').evaluate().isNotEmpty) await type(tester, keyed('stockQty'), '10');
          final exp = find.bySemanticsLabel('သက်တမ်းကုန်ရက်');
          await tester.ensureVisible(exp.last);
          await settle(tester);
          await tester.tap(exp.last);
          await inspect('add_product', choose: true);
          await shot(tester, 'r16_bug54_add_product_form_after_pick');
          await save();
        }
        final pb = await product('QA r16 Batch');
        note('batch product $pb; batches=${await q('SELECT batchNo, expiryDate FROM productBatches WHERE productId = ?', [pb?['id']])}');

        // 2. "Stock ဖြည့်မယ်" → "+ Batch အသစ်"
        app.router.go(Routes.products);
        await settle(tester);
        final restock = find.byKey(ValueKey('restock-${pb!['id']}'));
        await tester.ensureVisible(restock);
        await settle(tester);
        await tester.tap(restock);
        await settle(tester);
        if (find.byKey(const ValueKey('restockBatch-new')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const ValueKey('restockBatch-new')));
          await settle(tester);
        }
        await shot(tester, 'r16_bug54_restock_sheet');
        await tester.tap(find.byKey(const ValueKey('restockExpiry')));
        await inspect('restock', choose: false);
        await tester.binding.handlePopRoute(); // close the sheet
        await settle(tester);

        // 3. Edit form → "Batch အသစ်" expiry
        app.router.go(Routes.products);
        await settle(tester);
        await tapText(tester, 'QA r16 Batch');
        await settle(tester);
        final nb = find.byKey(const ValueKey('newBatchExpiry'));
        await tester.scrollUntilVisible(nb, 300, scrollable: find.byType(Scrollable).first); // lazily built below the fold
        await tester.ensureVisible(nb);
        await settle(tester);
        await shot(tester, 'r16_bug54_edit_form');
        await tester.tap(nb);
        await inspect('edit_form', choose: false);
        app.router.go(Routes.products);
        await settle(tester);

      // ------------------------------------------------------------------------------------------ pull (iOS smoke)
      case 'pull':
        await syncNow('pull');
        for (final r in await q('SELECT no, total, method, voidedAt FROM sales ORDER BY createdAt')) {
          note('sale $r');
        }
        for (final r in await q('SELECT name, phone FROM customers ORDER BY phone')) {
          note('customer $r');
        }
        app.router.go(Routes.sales);
        await settle(tester);
        await shot(tester, 'r16_android_sales_after_ios');

      default:
        fail('unknown QA_STEP "$step"');
    }
    note('FAILURES: ${failures.length} ${failures.join(' | ')}');
    expect(failures, isEmpty);
  });
}
