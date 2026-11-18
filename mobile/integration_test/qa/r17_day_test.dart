// QA round 17: the owner's "Localhost Manual Test Checklist" (a shop owner's day), automated.
// Phone P = the real iPhone (profile build launched without a driver, reports to r17_host.py; see r17_ios_device.sh),
// phone A = the Android emulator (run_qa_android.sh). Both run against the live API on the Mac (scratch DB).
// The app starts exactly like lib/main.dart (Drift "zaypos", the real secure store, the restored open cart).
//
// QA_STEP (checklist numbers in brackets):
//   P register  [1]   register a grocery shop with the preset catalog; first download; Home
//   P reopen    [2]   a new process opens on the PIN screen; PIN unlocks
//   P day       [4 5 6 7 8 12 15 16 17]  restock, sales (barcode typed, no-price, KBZPay, debt), repayments, edit customer, void
//   A signin    [20]  sign in to the same shop; every iPhone sale is there
//   A cart_add / cart_check  [9]  item in the cart, force-stop (host), reopen: cart restored
//   A offline   [18 19]  airplane mode on (host), 2 sales, airplane mode off: they sync without a manual sync
//   A edit      [21]  change a price and delete a barcode, sync
//   P verify    [21 22]  the change reached the iPhone; Dashboard / Reports vs the server DB (QA_EXPECT from the host)
//   A totals    [22]  Dashboard / Reports vs the server DB on Android
//   A font      [24]  largest font: POS buttons visible, no overflow
//   P pinlock   [23]  5 wrong PINs: 15-minute lockout
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/utils/money_format.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/features/pos/data/cart_store.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/main.dart';

import 'qa_harness.dart';
import 'r17_io.dart';

// QA_STEP=fromhost: the step and QA_EXPECT come from r17_host.py (GET QA_STEP_HOST/step → "<step>|<expect>"), so ONE
// Android APK serves every step and `flutter drive` never reinstalls it (a reinstall wiped the app data: low storage).
const _stepDefine = String.fromEnvironment('QA_STEP');
const _expectDefine = String.fromEnvironment('QA_EXPECT'); // "sales=..;profit=..;unknown=..;count=..;debt=..;debtors=.."
const _stepHost = String.fromEnvironment('QA_STEP_HOST', defaultValue: 'http://10.0.2.2:8765');
String step = _stepDefine;
String expectArg = _expectDefine;

Future<void> _loadStep() async {
  if (_stepDefine != 'fromhost') return;
  final hc = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final r = await (await hc.getUrl(Uri.parse('${qaHost.isNotEmpty ? qaHost : _stepHost}/step'))).close();
  final parts = (await r.transform(const SystemEncoding().decoder).join()).split('|');
  hc.close();
  step = parts[0].trim();
  expectArg = parts.length > 1 ? parts[1].trim() : '';
  if (parts.length > 2 && parts[2].trim().isNotEmpty) runName = parts[2].trim();
}
const shopLocal = String.fromEnvironment('QA_SHOP', defaultValue: '9 790 917 171');
final shopE164 = '+95${shopLocal.replaceAll(' ', '')}';
const shopName = String.fromEnvironment('QA_SHOP_NAME', defaultValue: 'QA r17 ကုန်စုံ');
const pin = '111111';
const salt = 'ဆား';
const egg = 'ကြက်ဥ';
const sugar = 'သကြား';
const barcode = '8850999171001';
const debtorName = 'QA r17 ဒေါ်မြ';
const debtorPhone = '09790917172';
const debtorPhone2 = '09790917173';

Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

/// Starts the app exactly like lib/main.dart (incl. the open cart restore that qa_harness.launchApp leaves out).
Future<QaApp> launchMain(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final db = AppDatabase(driftDatabase(name: 'zaypos'));
  const store = FlutterSecureStore();
  final boot = await bootstrap(db, store);
  final limits = await loadLimits(db);
  final cart = await loadOpenCart(db);
  final c = ProviderContainer(overrides: [
    ...driftOverrides(db, boot, store),
    initialLimitsProvider.overrideWithValue(limits),
    initialCartProvider.overrideWithValue(CartRestore(cart)),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
  await settle(tester);
  return QaApp(c, db);
}

/// All visible text (Text and RichText), for "is this value on screen" checks.
List<String> screenTexts() {
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    out.add((e.widget as RichText).text.toPlainText());
  }
  return out;
}

bool onScreen(String s) => screenTexts().any((t) => t.contains(s));

Future<bool> waitUntil(WidgetTester tester, bool Function() ok, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 200));
  }
  return true;
}

const _digits = [
  (LogicalKeyboardKey.digit0, PhysicalKeyboardKey.digit0), (LogicalKeyboardKey.digit1, PhysicalKeyboardKey.digit1),
  (LogicalKeyboardKey.digit2, PhysicalKeyboardKey.digit2), (LogicalKeyboardKey.digit3, PhysicalKeyboardKey.digit3),
  (LogicalKeyboardKey.digit4, PhysicalKeyboardKey.digit4), (LogicalKeyboardKey.digit5, PhysicalKeyboardKey.digit5),
  (LogicalKeyboardKey.digit6, PhysicalKeyboardKey.digit6), (LogicalKeyboardKey.digit7, PhysicalKeyboardKey.digit7),
  (LogicalKeyboardKey.digit8, PhysicalKeyboardKey.digit8), (LogicalKeyboardKey.digit9, PhysicalKeyboardKey.digit9),
];

/// A HID barcode scanner: digit key events in a fast burst, then Enter (no camera).
Future<void> hidType(WidgetTester tester, String code) async {
  for (final ch in code.split('')) {
    final (l, p) = _digits[int.parse(ch)];
    await simulateKeyDownEvent(l, physicalKey: p, character: ch);
    await simulateKeyUpEvent(l, physicalKey: p);
  }
  await simulateKeyDownEvent(LogicalKeyboardKey.enter, physicalKey: PhysicalKeyboardKey.enter);
  await simulateKeyUpEvent(LogicalKeyboardKey.enter, physicalKey: PhysicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  qaBinding();

  testWidgets('r17 day: $_stepDefine', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    await _loadStep();
    final ck = Checks();
    rnote('start step=$step run=$qaRun platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion} api=$apiBaseUrl');
    final app = await launchMain(tester);
    final c = app.container;
    final db = app.db;
    c.listen(customerAccountsProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));
    final problems = <String>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = '${d.exceptionAsString().split('\n').first} @ ${app.router.location}';
      problems.add(s);
      rnote('FlutterError: $s');
    };

    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
        (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get()).map((r) => r.data).toList();
    Future<int> one(String sql, [List<Object?> args = const []]) async => ((await q(sql, args)).first.values.first as int?) ?? 0;
    Future<Map<String, Object?>?> product(String name) async {
      final r = await q(
          'SELECT p.id, p.name, p.price, p.cost, p.barcode, '
          '(SELECT COALESCE(SUM(m.qtyMilli),0) FROM stockMovements m WHERE m.productId=p.id AND m.deletedAt IS NULL) stock, '
          '(SELECT COUNT(*) FROM stockMovements m WHERE m.productId=p.id AND m.deletedAt IS NULL) moves '
          'FROM products p WHERE p.name = ? AND p.deletedAt IS NULL',
          [name]);
      return r.isEmpty ? null : r.first;
    }

    Future<int> outbox() => one('SELECT COUNT(*) FROM outbox');
    Future<void> syncNow(String why) async {
      final t = DateTime.now();
      await c.read(syncEngineProvider).syncNow(manual: true);
      await settle(tester);
      final snap = c.read(syncEngineProvider).snapshot;
      rnote('sync ($why) ${DateTime.now().difference(t).inMilliseconds} ms; outbox=${await outbox()} '
          'lastError=${snap.lastError} online=${snap.online}');
    }

    Future<void> unlock() async {
      if (find.text('PIN နံပါတ် ထည့်ပါ').evaluate().isEmpty) return;
      for (final d in pin.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump(const Duration(milliseconds: 120));
      }
      final ok = await waitUntil(tester, () => c.read(authControllerProvider).status == AuthStatus.unlocked);
      ck.that(ok, 'PIN $pin unlocks');
      await wait(tester, const Duration(seconds: 2));
    }

    Future<void> save() async {
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await settle(tester);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await wait(tester, const Duration(seconds: 2));
    }

    Cart cart() => c.read(cartProvider);
    Future<void> openPos() async {
      app.router.go(Routes.pos);
      await settle(tester);
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
    }

    Future<void> tapProductTile(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      final f = find.text(name);
      final grid = find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable));
      if (f.evaluate().isEmpty && grid.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(f, 250, scrollable: grid.first, maxScrolls: 60);
      }
      // keep the tile well above the floating cart bar
      await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.2);
      await settle(tester);
      await tester.tap(f.first);
      await settle(tester);
    }

    Future<Map<String, Object?>> lastSale() async =>
        (await q('SELECT id, no, method, total, customerId, voidedAt FROM sales ORDER BY createdAt DESC LIMIT 1')).first;

    Future<Map<String, Object?>> checkout(String method, {String? customer, required String shotName}) async {
      await tapText(tester, 'ငွေရှင်းမယ်');
      if (method != 'ငွေသား') await tapText(tester, method);
      if (customer != null) {
        await tapText(tester, 'ဖောက်သည် ရွေးပါ');
        await tapText(tester, customer, last: true);
      }
      await snap(tester, '${shotName}_checkout');
      await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
      final ok = await waitUntil(tester, () => find.text('ရောင်းပြီးပါပြီ').evaluate().isNotEmpty);
      ck.that(ok, '$shotName: receipt screen "ရောင်းပြီးပါပြီ" shows');
      await snap(tester, '${shotName}_receipt');
      final s = await lastSale();
      rnote('$shotName: sale $s');
      return s;
    }

    Future<String> customerId(String name) async =>
        (await q('SELECT id FROM customers WHERE name = ? AND deletedAt IS NULL', [name])).first['id']! as String;
    int balanceOf(String id) =>
        (c.read(customerAccountsProvider).value ?? const []).firstWhere((a) => a.id == id).balance;

    Future<void> payDebt(String id, {int? amount, required String shotName}) async {
      app.router.go(Routes.customer(id));
      await settle(tester);
      await tapText(tester, 'ငွေပြန်ဆပ်မယ်');
      if (amount != null) {
        await typeR(tester, field('ဆပ်မယ့်ပမာဏ'), '$amount');
      } else {
        await tapText(tester, 'အကုန်ဆပ်');
      }
      await snap(tester, '${shotName}_sheet');
      final accept = find.textContaining('လက်ခံမယ်').last;
      rnote('$shotName: tapping "${(accept.evaluate().first.widget as Text).data}"');
      await tester.tap(accept);
      await wait(tester, const Duration(seconds: 2));
      await snap(tester, '${shotName}_after');
    }

    // ------------------------------------------------------------------------------------------------------ steps
    try {
    switch (step) {
      // ==================================================================================== [1] register (P)
      case 'register':
        rnote('auth at launch: ${c.read(authControllerProvider).status}');
        if (find.text('တခြားအကောင့်နဲ့ ဝင်မယ်').evaluate().isNotEmpty) {
          rnote('the phone opened on the PIN screen of an older install: "တခြားအကောင့်နဲ့ ဝင်မယ်"');
          await tapText(tester, 'တခြားအကောင့်နဲ့ ဝင်မယ်');
          await wait(tester, const Duration(seconds: 2));
        }
        rnote('login screen texts: ${screenTexts().where((t) => t.length < 120).toList()}');
        await snap(tester, 'r17_P1_login');
        await tapText(tester, 'ဆိုင်အသစ် စာရင်းသွင်းမယ်');
        await typeR(tester, field('ဖုန်းနံပါတ်'), shopLocal);
        final before = await otpCountR(shopE164);
        rnote('register screen texts: ${screenTexts().where((t) => t.length < 80).toList()}');
        await tapText(tester, 'ကုဒ်ပို့မယ်');
        await wait(tester, const Duration(seconds: 3));
        rnote('after "ကုဒ်ပို့မယ်": ${screenTexts().where((t) => t.length < 120).toList()}');
        await snap(tester, 'r17_P1_code_sent');
        final code = await otpForR(tester, shopE164, after: before);
        rnote('OTP received from the API log (6 digits)');
        await waitFor(tester, find.text('အတည်ပြုကုဒ်'));
        await typeR(tester, find.byType(EditableText).last, code);
        await settle(tester);
        await tapText(tester, 'ဆက်သွားမယ်');
        await typeR(tester, field('ဆိုင်အမည်'), shopName);
        await tapText(tester, 'ကုန်စုံဆိုင်');
        await snap(tester, 'r17_P1_step2_shop');
        await tapText(tester, 'ဆက်သွားမယ်');
        await tapText(tester, 'ကြိုတင်စာရင်း သုံးမယ် (အကြံပြု)');
        await snap(tester, 'r17_P1_step3_preset');
        await tapText(tester, 'ဆက်သွားမယ်');
        for (final d in pin.split('')) {
          await tester.tap(find.text(d).last);
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tapText(tester, 'ဆိုင်ဖွင့်မယ်');
        var sawFirstSync = false;
        final end = DateTime.now().add(const Duration(seconds: 90));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
          if (app.router.location == Routes.firstSync && !sawFirstSync) {
            sawFirstSync = true;
            await snap(tester, 'r17_P1_first_sync');
          }
          if (c.read(authControllerProvider).status == AuthStatus.unlocked &&
              c.read(firstSyncDoneProvider) &&
              app.router.location == Routes.dashboard) {
            break;
          }
        }
        final auth = c.read(authControllerProvider);
        rnote('after register: status=${auth.status} notice=${auth.notice} firstSyncDone=${c.read(firstSyncDoneProvider)} '
            'route=${app.router.location} sawFirstSyncScreen=$sawFirstSync');
        ck.that(auth.status == AuthStatus.unlocked, 'signed in after "ဆိုင်ဖွင့်မယ်"', auth.status);
        ck.that(c.read(firstSyncDoneProvider), 'first download finished');
        ck.that(app.router.location == Routes.dashboard, 'Home (dashboard) opens', app.router.location);
        ck.that(auth.notice == null, 'no notice (presets downloaded)', auth.notice);
        await wait(tester, const Duration(seconds: 3));
        await snap(tester, 'r17_P1_home');
        final snap1 = c.read(syncEngineProvider).snapshot;
        ck.that(snap1.lastError == null, 'no sync error after the first download', snap1.lastError);
        final n = await one('SELECT COUNT(*) FROM products WHERE deletedAt IS NULL');
        ck.that(n == 20, '20 preset products on the phone', n);
        await syncNow('push presets');
        await wait(tester, const Duration(seconds: 3));
        final ob = await outbox();
        ck.that(ob == 0, 'outbox empty after the first push', ob);
        final snap2 = c.read(syncEngineProvider).snapshot;
        ck.that(snap2.lastError == null, 'no sync error after the push', snap2.lastError);
        for (final r in await q('SELECT status, COUNT(*) n FROM outbox GROUP BY status')) {
          rnote('outbox $r');
        }

      // ==================================================================================== [2] reopen (P)
      case 'reopen':
        final status = c.read(authControllerProvider).status;
        final pinScreen = find.text('PIN နံပါတ် ထည့်ပါ').evaluate().isNotEmpty;
        rnote('new process: auth=$status route=${app.router.location} PIN screen=$pinScreen');
        await snap(tester, 'r17_P2_reopen_pin_screen');
        ck.that(pinScreen && app.router.location == Routes.unlock, 'reopened app shows the PIN screen', app.router.location);
        await unlock();
        await snap(tester, 'r17_P2_after_unlock');
        ck.that(app.router.location == Routes.dashboard, 'after the PIN: Home', app.router.location);
        ck.that(onScreen(shopName), 'Home shows the shop name');

      // ==================================================================================== the day (P)
      case 'day':
        await unlock();
        // --- set up: barcode + price + cost on ဆား, price + cost on ကြက်ဥ (owner enters prices at day start)
        Future<void> edit(String name, {String? bc, required String cost, required String price}) async {
          final p = await product(name);
          app.router.push(Routes.editProduct(p!['id']! as String));
          await settle(tester);
          if (bc != null) await typeR(tester, keyed('barcode'), bc);
          await typeR(tester, keyed('cost'), cost);
          await typeR(tester, keyed('price'), price);
          await snap(tester, 'r17_P_edit_${name == salt ? 'salt' : 'egg'}');
          await save();
          rnote('edited $name: ${await product(name)}');
        }

        if ((await product(salt))!['barcode'] == null) await edit(salt, bc: barcode, cost: '400', price: '500');
        if ((await product(egg))!['price'] == 0) await edit(egg, cost: '250', price: '300');

        // --- [4] restock 3 products (untracked → opening count; then a second restock of a tracked one)
        Future<void> restock(String name, String qty) async {
          app.router.go(Routes.products);
          await settle(tester);
          final p = await product(name);
          final btn = find.byKey(ValueKey('restock-${p!['id']}'));
          await tester.scrollUntilVisible(btn, 200, scrollable: find.byType(Scrollable).first);
          await settle(tester);
          await tester.tap(btn);
          await settle(tester);
          for (final d in qty.split('')) {
            await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(d)).last);
            await tester.pump(const Duration(milliseconds: 80));
          }
          await settle(tester);
          await snap(tester, 'r17_P4_restock_${p['id'].toString().substring(0, 6)}_$qty');
          await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('သိမ်းမယ်')).last);
          await wait(tester, const Duration(seconds: 1));
        }

        final stock0 = {for (final n in [salt, egg, sugar]) n: (await product(n))!['stock'] as int};
        rnote('[4] stock before: $stock0');
        final restockDone = (await product(salt))!['moves'] as int > 0;
        if (restockDone) {
          rnote('[4] restock already done by an earlier run of this step; not repeated');
        } else {
          await restock(salt, '10');
          await restock(egg, '30');
          await restock(sugar, '5');
          await restock(salt, '5');
        }
        final stock4 = {for (final n in [salt, egg, sugar]) n: (await product(n))!['stock'] as int};
        rnote('[4] stock after: $stock4');
        ck.that(stock4[salt] == 15000 && stock4[egg] == 30000 && stock4[sugar] == 5000,
            '[4] stock ဆား 15, ကြက်ဥ 30, သကြား 5 (10 + 5 / 30 / 5)', stock4);
        app.router.go(Routes.products);
        await settle(tester);
        await snap(tester, 'r17_P4_products_after_restock');

        // --- [5] cash sale, barcode typed like a HID scanner (no camera)
        await openPos();
        if (cart().lines.isNotEmpty) {
          rnote('[5] cart restored from an earlier run: ${cart().lines.map((l) => '${l.name}×${l.qtyMilli}').toList()}; cleared');
          c.read(cartProvider.notifier).clear();
          await settle(tester);
        }
        await tester.tap(find.byType(EditableText).first);
        await settle(tester);
        await hidType(tester, barcode);
        await settle(tester);
        await tapProductTile(salt); // second ဆား by tap
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        rnote('[5] cart after typed barcode + tap: ${cart().lines.map((l) => '${l.name}×${l.qtyMilli}').toList()}');
        ck.that(cart().lines.length == 1 && cart().lines.single.name == salt && cart().lines.single.qtyMilli == 2000,
            '[5] typed barcode adds ဆား (2 with the tap)', cart().lines.map((l) => '${l.name}×${l.qtyMilli}').toList());
        final cash = await checkout('ငွေသား', shotName: 'r17_P5_cash');
        ck.that(cash['method'] == 'cash' && cash['total'] == 1000, '[5] cash sale 1,000 Ks', cash);
        ck.that(onScreen('1,000'), '[5] receipt shows 1,000');
        final s5 = (await product(salt))!['stock'];
        ck.that(s5 == 13000, '[5] ဆား stock 15 → 13', s5);

        // --- [6] product with no selling price: POS asks for it
        await openPos();
        await tapProductTile(sugar);
        final asked = find.text('ဈေးနှုန်း ထည့်ပါ').evaluate().isNotEmpty;
        await snap(tester, 'r17_P6_asks_price');
        ck.that(asked, '[6] POS asks "ဈေးနှုန်း ထည့်ပါ" for သကြား (price 0)');
        if (asked) {
          for (final d in '6500'.split('')) {
            await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(d)).last);
            await tester.pump(const Duration(milliseconds: 80));
          }
          await settle(tester);
          await tapText(tester, 'သိမ်းပြီး ခြင်းထဲထည့်မယ်');
          final s6 = await checkout('ငွေသား', shotName: 'r17_P6_noprice');
          ck.that(s6['total'] == 6500, '[6] sale at the entered price 6,500', s6);
          ck.that((await product(sugar))!['price'] == 6500, '[6] price saved on the product');
        }

        // --- [7] KBZPay
        await openPos();
        for (var i = 0; i < 3; i++) {
          await tapProductTile(egg);
        }
        final kbz = await checkout('KBZPay', shotName: 'r17_P7_kbz');
        ck.that(kbz['method'] == 'kbz' && kbz['total'] == 900, '[7] KBZPay sale 900 Ks, method kbz', kbz);
        rnote('[7] receipt shows the method "KBZPay": ${onScreen('KBZPay')} (receipt card texts: '
            '${screenTexts().where((t) => t.length < 60).toList()})');
        final pendingAtReceipt = onScreen('လိုင်းမရှိဘဲ သိမ်းထားသည်');
        final tp = DateTime.now();
        final gone = await waitUntil(tester, () => !onScreen('လိုင်းမရှိဘဲ သိမ်းထားသည်'), timeout: const Duration(seconds: 20));
        rnote('[7] online receipt said "လိုင်းမရှိဘဲ သိမ်းထားသည်" at first: $pendingAtReceipt; gone after sync: $gone '
            'in ${DateTime.now().difference(tp).inMilliseconds} ms; outbox=${await outbox()}');
        await snap(tester, 'r17_P7_kbz_receipt_after_sync');
        app.router.go(Routes.sale(kbz['id']! as String));
        await settle(tester);
        await snap(tester, 'r17_P7_kbz_sale_detail');
        ck.that(onScreen('KBZPay'), '[7] sale detail shows payment method "KBZPay"');

        // --- [8] debt to a new customer
        if ((await q('SELECT 1 FROM customers WHERE name = ?', [debtorName])).isEmpty) {
          app.router.go(Routes.customers);
          await settle(tester);
          await tapText(tester, 'ဖောက်သည်အသစ်');
          await typeR(tester, field('အမည်'), debtorName);
          await typeR(tester, field('ဖုန်းနံပါတ်'), debtorPhone);
          await snap(tester, 'r17_P8_new_customer');
          await save();
        }
        final cid = await customerId(debtorName);
        await openPos();
        for (var i = 0; i < 4; i++) {
          await tapProductTile(salt);
        }
        final debt = await checkout('အကြွေး', customer: debtorName, shotName: 'r17_P8_debt');
        ck.that(debt['method'] == 'debt' && debt['total'] == 2000 && debt['customerId'] == cid,
            '[8] debt sale 2,000 Ks for the new customer', debt);
        app.router.go(Routes.customers);
        await settle(tester);
        if (find.text('အကြွေးရှိသူ').evaluate().isNotEmpty) await tapText(tester, 'အကြွေးရှိသူ');
        await snap(tester, 'r17_P8_debts_list');
        ck.that(onScreen(debtorName), '[8] the customer is in the debts list');
        ck.that(balanceOf(cid) == 2000, '[8] balance 2,000', balanceOf(cid));
        ck.that(onScreen('2,000'), '[8] list shows 2,000');

        // --- [12] half repayment
        await payDebt(cid, amount: 1000, shotName: 'r17_P12_half');
        ck.that(balanceOf(cid) == 1000, '[12] remaining 1,000 after paying 1,000', balanceOf(cid));
        ck.that(onScreen('1,000 Ks'), '[12] debt screen shows 1,000 Ks');
        ck.that(find.text(debtRemindLabel).evaluate().isNotEmpty, '[16 pre] "Viber သတိပေး" shown while 1,000 is owed');

        // --- [15] edit customer: phone + credit limit; remaining shown next to the limit
        app.router.push(Routes.editCustomer(cid));
        await settle(tester);
        await typeR(tester, field('ဖုန်းနံပါတ်'), debtorPhone2);
        await typeR(tester, field('အကြွေး ကန့်သတ်ချက်'), '50000');
        final balWidget = find.byKey(const ValueKey('currentBalance'));
        final balTexts = balWidget.evaluate().isEmpty
            ? <String>[]
            : find.descendant(of: balWidget, matching: find.byType(RichText)).evaluate().map((e) => (e.widget as RichText).text.toPlainText()).toList();
        await snap(tester, 'r17_P15_edit_customer');
        ck.that(balTexts.contains('လက်ရှိ အကြွေး') && balTexts.contains('1,000 Ks'),
            '[15] "လက်ရှိ အကြွေး 1,000 Ks" next to the credit limit', balTexts);
        await save();
        final cu = (await q('SELECT phone, creditLimit FROM customers WHERE id = ?', [cid])).first;
        ck.that(cu['phone'].toString().replaceAll(' ', '') == debtorPhone2 && cu['creditLimit'] == 50000,
            '[15] saved: phone $debtorPhone2, limit 50,000', cu);
        app.router.go(Routes.customer(cid));
        await settle(tester);
        await snap(tester, 'r17_P15_debt_screen_after_edit');

        // --- [16] repay fully: "Viber သတိပေး" disappears
        await payDebt(cid, shotName: 'r17_P16_full');
        ck.that(balanceOf(cid) == 0, '[16] balance 0', balanceOf(cid));
        ck.that(find.text(debtRemindLabel).evaluate().isEmpty, '[16] "Viber သတိပေး" gone');

        // --- [17] void the cash sale: stock back, receipt stamp "ပယ်ဖျက်ပြီး"
        final before17 = (await product(salt))!['stock'];
        final soldQty = await one('SELECT COALESCE(SUM(qtyMilli),0) FROM saleLines WHERE saleId = ?', [cash['id']]);
        app.router.go(Routes.sale(cash['id']! as String));
        await settle(tester);
        await tapText(tester, 'ပယ်ဖျက်မယ်');
        await wait(tester, const Duration(seconds: 1));
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          rnote('[17] a confirm dialog appeared: ${screenTexts().where((t) => t.length < 60).toList()}');
          await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
          await wait(tester, const Duration(seconds: 1));
        }
        await snap(tester, 'r17_P17_sale_voided');
        final after17 = (await product(salt))!['stock'];
        final v = (await q('SELECT voidedAt FROM sales WHERE id = ?', [cash['id']])).first['voidedAt'];
        ck.that(v != null, '[17] sale voided');
        ck.that(after17 == (before17! as int) + soldQty, '[17] ဆား stock +$soldQty milli back ($before17 → $after17)', after17);
        app.router.go(Routes.receipt(cash['id']! as String));
        await settle(tester);
        await snap(tester, 'r17_P17_receipt_voided');
        ck.that(find.text('ပယ်ဖျက်ပြီး').evaluate().isNotEmpty, '[17] receipt shows "ပယ်ဖျက်ပြီး"');

        await syncNow('end of day part 1');
        await wait(tester, const Duration(seconds: 2));
        await syncNow('again');
        ck.that(await outbox() == 0, 'P: everything pushed (outbox 0)', await outbox());
        for (final r in await q('SELECT no, method, total, voidedAt IS NOT NULL voided FROM sales ORDER BY createdAt')) {
          rnote('P sale $r');
        }
        for (final n in [salt, egg, sugar]) {
          rnote('P product ${await product(n)}');
        }

      // ==================================================================================== [20] signin (A)
      case 'signin':
        if (find.text('ဝင်မယ်').evaluate().isNotEmpty) {
          await typeR(tester, field('ဖုန်းနံပါတ်'), shopLocal);
          await typeR(tester, field('PIN နံပါတ်'), pin);
          await snap(tester, 'r17_A20_login_filled');
          await tapText(tester, 'ဝင်မယ်');
          final signedIn = await waitUntil(tester, () => c.read(authControllerProvider).status == AuthStatus.unlocked,
              timeout: const Duration(seconds: 40));
          ck.that(signedIn, '[20] signed in on Android with the iPhone shop phone + PIN');
          if (!signedIn) rnote('[20] login screen: ${screenTexts().where((t) => t.length < 120).toList()}');
        }
        final ok = await waitUntil(tester, () => c.read(firstSyncDoneProvider), timeout: const Duration(seconds: 60));
        ck.that(ok, '[20] first download finished on Android');
        await syncNow('pull');
        final expected = int.tryParse(expectArg) ?? -1;
        final sales = await q('SELECT no, method, total, voidedAt IS NOT NULL voided FROM sales ORDER BY createdAt');
        for (final r in sales) {
          rnote('A sale $r');
        }
        ck.that(sales.length == expected, '[20] all $expected iPhone sales are on Android', sales.length);
        app.router.go(Routes.sales);
        await settle(tester);
        await snap(tester, 'r17_A20_sales_list');
        ck.that(find.text('ပယ်ဖျက်ပြီး').evaluate().isNotEmpty, '[20] the voided sale shows as voided');
        for (final n in [salt, egg, sugar]) {
          rnote('A product ${await product(n)}');
        }

      // ==================================================================================== [9] cart (A)
      case 'cart_add':
        await unlock();
        await openPos();
        cart().lines.isEmpty ? null : c.read(cartProvider.notifier).clear();
        await tapProductTile(egg);
        await tapProductTile(egg);
        await tapProductTile(salt);
        await settle(tester);
        await snap(tester, 'r17_A9_cart_before_kill');
        rnote('[9] cart before kill: ${cart().lines.map((l) => '${l.name}×${l.qtyMilli}').toList()} total=${cart().total}');
        ck.that(cart().lines.length == 2, '[9] 2 lines in the cart');
        await wait(tester, const Duration(seconds: 2)); // the cart store writes after a short delay
      case 'cart_check':
        await unlock();
        await openPos();
        await snap(tester, 'r17_A9_cart_after_reopen');
        final lines = cart().lines.map((l) => '${l.name}×${l.qtyMilli}').toList();
        rnote('[9] cart after force-stop + reopen: $lines total=${cart().total}');
        ck.that(lines.length == 2 && lines.contains('$egg×2000') && lines.contains('$salt×1000'),
            '[9] cart restored (ကြက်ဥ×2, ဆား×1)', lines);
        ck.that(onScreen('ပစ္စည်း 3 ခု'), '[9] cart bar shows "ပစ္စည်း 3 ခု"');
        c.read(cartProvider.notifier).clear();
        await wait(tester, const Duration(seconds: 2));

      // ==================================================================================== [18-19] offline (A)
      case 'offline':
        await unlock();
        await syncNow('before airplane');
        final salesBefore = await one('SELECT COUNT(*) FROM sales');
        // the host switches airplane mode on now and off again after 90 s (the app cannot reach the host while offline)
        final tOn = DateTime.now();
        await hcmd(tester, 'airplane_window_90');
        await wait(tester, const Duration(seconds: 8));
        // positive control: the API is really unreachable now
        String probe;
        try {
          final hc = HttpClient()..connectionTimeout = const Duration(seconds: 5);
          final r = await (await hc.getUrl(Uri.parse('$apiBaseUrl/api/v1/sync/pull'))).close().timeout(const Duration(seconds: 8));
          probe = 'HTTP ${r.statusCode}';
        } catch (e) {
          probe = 'failed: ${e.runtimeType}';
        }
        rnote('[18] API probe in airplane mode: $probe');
        ck.that(probe.startsWith('failed'), '[18] airplane mode cuts the API', probe);
        final ids = <String>[];
        // offline sale 1: cash; offline sale 2: on debt (so [22] has a debt outstanding)
        for (final (i, name) in [egg, salt].indexed) {
          await openPos();
          await tapProductTile(name);
          final s = i == 0
              ? await checkout('ငွေသား', shotName: 'r17_A18_offline_1')
              : await checkout('အကြွေး', customer: debtorName, shotName: 'r17_A18_offline_2');
          ids.add(s['id']! as String);
          ck.that(onScreen('လိုင်းမရှိဘဲ သိမ်းထားသည်'), '[18] receipt ${i + 1} says saved offline');
        }
        final ob = await outbox();
        rnote('[18] outbox while offline: $ob');
        ck.that(ob >= 2, '[18] the 2 sales wait in the outbox', ob);
        // no manual sync: the app must push by itself when the network comes back (host: airplane off at tOn + 90 s)
        final left = const Duration(seconds: 87) - DateTime.now().difference(tOn);
        rnote('[19] airplane mode goes off in ${left.inSeconds + 3} s; outbox still $ob');
        if (left > Duration.zero) await wait(tester, left);
        ck.that(await outbox() >= 2, '[18] still waiting in the outbox right before airplane mode goes off', await outbox());
        final t0 = DateTime.now();
        var pushed = false;
        final end19 = DateTime.now().add(const Duration(seconds: 180));
        while (!pushed && DateTime.now().isBefore(end19)) {
          await wait(tester, const Duration(seconds: 2));
          pushed = await outbox() == 0;
        }
        rnote('[19] outbox empty without a manual sync: $pushed after ${DateTime.now().difference(t0).inSeconds} s');
        ck.that(pushed, '[19] the 2 offline sales sync by themselves after airplane mode off');
        ck.that(await one('SELECT COUNT(*) FROM sales') == salesBefore + 2, '[18] 2 new sales on the phone');
        for (final id in ids) {
          rnote('[19] offline sale id=$id ${(await q('SELECT no, total, syncedAt FROM sales WHERE id = ?', [id])).first}');
        }
        app.router.go(Routes.sales);
        await settle(tester);
        await snap(tester, 'r17_A19_sales_after_reconnect');

      // ==================================================================================== [21] edit (A)
      case 'edit':
        await unlock();
        await syncNow('before edit');
        final e = await product(egg);
        app.router.push(Routes.editProduct(e!['id']! as String));
        await settle(tester);
        await typeR(tester, keyed('price'), '350');
        await snap(tester, 'r17_A21_edit_price');
        await save();
        final s = await product(salt);
        app.router.push(Routes.editProduct(s!['id']! as String));
        await settle(tester);
        await typeR(tester, keyed('barcode'), '');
        await snap(tester, 'r17_A21_delete_barcode');
        await save();
        rnote('[21] A after edit: ${await product(egg)} / ${await product(salt)}');
        ck.that((await product(egg))!['price'] == 350, '[21] A: ကြက်ဥ price 350');
        final bc = (await product(salt))!['barcode'];
        ck.that(bc == null || bc == '', '[21] A: ဆား barcode deleted', bc);
        await syncNow('push edit');
        ck.that(await outbox() == 0, '[21] A: edit pushed');

      // ==================================================================================== [21 22] verify (P) / [22] totals (A)
      case 'verify':
      case 'totals':
        await unlock();
        await syncNow('pull');
        if (step == 'verify') {
          final e = await product(egg);
          final s = await product(salt);
          rnote('[21] P after pull: $e / $s');
          ck.that(e!['price'] == 350, '[21] iPhone: ကြက်ဥ price 350 (changed on Android)', e['price']);
          ck.that(s!['barcode'] == null || s['barcode'] == '', '[21] iPhone: ဆား barcode deleted', s['barcode']);
          await openPos();
          await tester.tap(find.byType(EditableText).first);
          await settle(tester);
          await hidType(tester, barcode);
          await settle(tester);
          await snap(tester, 'r17_P21_old_barcode_scanned');
          ck.that(find.text('ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ').evaluate().isNotEmpty, '[21] iPhone: the old barcode no longer finds ဆား');
          if (find.text('မလုပ်တော့ပါ').evaluate().isNotEmpty) await tapText(tester, 'မလုပ်တော့ပါ');
          c.read(cartProvider.notifier).clear();
          await openPos();
          await tapProductTile(egg);
          ck.that(cart().lines.isNotEmpty && cart().lines.first.price == 350, '[21] iPhone POS sells ကြက်ဥ at 350',
              cart().lines.isEmpty ? null : cart().lines.first.price);
          c.read(cartProvider.notifier).clear();
          await settle(tester);
        }
        // [22] expected values computed on the host from the server DB
        final ex = {for (final kv in expectArg.split(';').where((s) => s.contains('='))) kv.split('=')[0]: int.parse(kv.split('=')[1])};
        rnote('[22] expected from the server DB: $ex');
        final tag = step == 'verify' ? 'P' : 'A';
        app.router.go(Routes.dashboard);
        await settle(tester);
        await wait(tester, const Duration(seconds: 2));
        await snap(tester, 'r17_${tag}22_dashboard');
        final dash = screenTexts();
        rnote('[22] $tag dashboard texts: ${dash.where((t) => RegExp(r'\d').hasMatch(t) && t.length < 40).toList()}');
        ck.that(dash.contains(formatKs(ex['sales']!)), '[22] $tag Dashboard today sales ${formatKs(ex['sales']!)}');
        ck.that(dash.contains('${ex['count']} ကြိမ်'), '[22] $tag Dashboard count ${ex['count']} ကြိမ်');
        ck.that(dash.contains(formatKs(ex['profit']!)), '[22] $tag Dashboard profit ${formatKs(ex['profit']!)}');
        if (ex['unknown']! > 0) {
          ck.that(dash.contains(unknownCostNote(ex['unknown']!)!), '[22] $tag Dashboard note "${unknownCostNote(ex['unknown']!)}"');
        }
        ck.that(dash.contains(formatMoney(ex['debt']!)), '[22] $tag Dashboard debt outstanding ${formatMoney(ex['debt']!)}');
        app.router.go(Routes.reports);
        await settle(tester);
        await wait(tester, const Duration(seconds: 2));
        await snap(tester, 'r17_${tag}22_reports');
        final rep = screenTexts();
        rnote('[22] $tag reports texts: ${rep.where((t) => RegExp(r'\d').hasMatch(t) && t.length < 40).toList()}');
        ck.that(rep.any((t) => t.startsWith('ရောင်းရငွေ · ')) && rep.contains(formatKs(ex['sales']!)),
            '[22] $tag Reports sales ${formatKs(ex['sales']!)}');
        ck.that(rep.contains(formatKs(ex['profit']!)), '[22] $tag Reports profit ${formatKs(ex['profit']!)}');
        ck.that(rep.contains('${ex['count']} ကြိမ်'), '[22] $tag Reports count');

      // ==================================================================================== [24] font (A)
      case 'font':
        await hcmd(tester, 'font_max');
        await wait(tester, const Duration(seconds: 3));
        await unlock();
        problems.clear();
        await openPos();
        await tapProductTile(egg);
        await tapProductTile(salt);
        await wait(tester, const Duration(seconds: 2));
        final scale = MediaQuery.of(tester.element(find.byType(Scaffold).first)).textScaler.scale(10) / 10;
        rnote('[24] text scale in the app: $scale');
        await snap(tester, 'r17_A24_pos_font_max');
        final screen = tester.getSize(find.byType(Scaffold).first);
        for (final label in ['ငွေရှင်းမယ်', 'ပစ္စည်းများ', 'အမြန်ရောင်း']) {
          final f = find.text(label);
          if (f.evaluate().isEmpty) {
            ck.that(false, '[24] "$label" is on the POS screen');
            continue;
          }
          final r = tester.getRect(f.first);
          final hit = f.hitTestable().evaluate().isNotEmpty;
          ck.that(hit && r.left >= 0 && r.right <= screen.width && r.bottom <= screen.height,
              '[24] "$label" visible and tappable at max font', '$r hit=$hit screen=$screen');
        }
        List<String> clipped() {
          final out = <String>[];
          void visit(RenderObject r) {
            if (r is RenderParagraph && r.attached && r.hasSize) {
              final txt = r.text.toPlainText();
              // a paragraph cut by maxLines / ellipsis, or a single word wider than its box (letters cut off)
              if (r.didExceedMaxLines) out.add('"$txt" cut (max lines)');
            }
            r.visitChildren(visit);
          }
          visit(RendererBinding.instance.renderViews.first);
          return out;
        }
        final posClipped = clipped();
        rnote('[24] POS texts cut at max font: $posClipped');
        await hcmd(tester, 'screencap_r17_A24_pos_font_max_screen');
        await wait(tester, const Duration(seconds: 3));
        ck.that(!posClipped.any((t) => t.contains('ငွေရှင်းမယ်') || t.contains('ပစ္စည်း')), '[24] POS cart bar / button texts not cut', posClipped);
        await tapText(tester, 'ငွေရှင်းမယ်');
        await snap(tester, 'r17_A24_checkout_font_max');
        rnote('[24] checkout texts cut at max font: ${clipped()}');
        await hcmd(tester, 'screencap_r17_A24_checkout_font_max_screen');
        await wait(tester, const Duration(seconds: 3));
        final confirm = find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်');
        ck.that(confirm.hitTestable().evaluate().isNotEmpty, '[24] checkout confirm button tappable at max font');
        ck.that(problems.isEmpty, '[24] no overflow / layout errors at max font', problems.toSet().toList());
        app.router.go(Routes.pos);
        await settle(tester);
        c.read(cartProvider.notifier).clear();
        await hcmd(tester, 'font_default');

      // ==================================================================================== [23] pinlock (P)
      case 'pinlock':
        ck.that(find.text('PIN နံပါတ် ထည့်ပါ').evaluate().isNotEmpty, '[23] opened on the PIN screen');
        for (var i = 1; i <= 5; i++) {
          for (final d in '000000'.split('')) {
            await tester.tap(find.text(d).last);
            await tester.pump(const Duration(milliseconds: 120));
          }
          await wait(tester, const Duration(seconds: 2));
          final msg = screenTexts().where((t) => t.contains('PIN မှား')).toList();
          rnote('[23] wrong PIN $i → $msg');
          if (i == 4) ck.that(msg.any((m) => m.contains(AuthMessages.wrongPin(1))), '[23] after 4: "1 more try"', msg);
          if (i == 5) {
            await snap(tester, 'r17_P23_locked');
            ck.that(msg.any((m) => m.contains('၁၅ မိနစ်')), '[23] after 5: "… ၁၅ မိနစ် ပိတ်ထားပါတယ်"', msg);
          }
        }
        final left = await c.read(authControllerProvider.notifier).lockRemaining();
        rnote('[23] lockRemaining=$left');
        ck.that(left != null && left.inMinutes >= 14 && left.inMinutes <= 15, '[23] locked for 15 minutes', left);
        for (final d in pin.split('')) {
          await tester.tap(find.text(d).last);
          await tester.pump(const Duration(milliseconds: 120));
        }
        await wait(tester, const Duration(seconds: 2));
        await snap(tester, 'r17_P23_correct_pin_while_locked');
        ck.that(c.read(authControllerProvider).status != AuthStatus.unlocked, '[23] the correct PIN is refused while locked',
            c.read(authControllerProvider).status);

      default:
        fail('QA_STEP missing');
    }
    } catch (e, st) {
      rnote('EXCEPTION ${e.toString().split('\n').take(6).join(' | ')}');
      rnote('STACK ${st.toString().split('\n').take(8).join(' | ')}');
      ck.failures.add('exception: ${e.toString().split('\n').first}');
      try {
        await snap(tester, 'r17_${qaRun}_EXCEPTION');
      } catch (_) {}
    }

    rnote('layout/framework problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    FlutterError.onError = oldOnError;
    await ck.finish(step);
    expect(ck.failures, isEmpty);
  });
}
