// QA round 14 — BUG-45 fix (3f89623) on the iOS simulator (phone A, real app, real share_plus + gal). Photos add permission
// is GRANTED by the host before each run (`xcrun simctl privacy … grant photos-add`). One share per run: the native share
// sheet stays open at the end, and `flutter drive` restarts the app for the next run.
//   valid        : sell 1 × soap → receipt screen (no stamp on screen) → "ပုံ သိမ်းမယ်" (runner `photos` copies the image)
//                  → "ပြေစာ ပို့မယ်" (runner `apptmp` copies the shared PNG).
//   void_detail  : void the newest sale on its screen → "ပြေစာ ပို့မယ်" from the SALE screen → `apptmp`.
//   void_receipt : the newest (voided) sale's RECEIPT screen (stamp on screen?) → "ပုံ သိမ်းမယ်" → `photos` → "ပြေစာ ပို့မယ်"
//                  → `apptmp`.
// The host then counts the stamp's red pixels in every copied PNG (scratchpad script, see round-14 summary).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';

import 'qa_harness.dart';

const step = String.fromEnvironment('QA_STEP', defaultValue: 'valid');
const soap = 'QA r12b ဆပ်ပြာ';

void main() {
  qaBinding();

  testWidgets('BUG-45 voided receipt stamp on the simulator ($step)', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    final c = app.container;
    c.listen(salesProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));

    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => problems.add('${d.exceptionAsString().split('\n').first} @ ${app.router.location}');
    addTearDown(() => FlutterError.onError = old);
    // Failures are collected and asserted at the end, after FlutterError.onError is restored (an check() failing while it
    // is replaced hides the real message behind a binding assertion).
    final failures = <String>[];
    void check(Object? actual, Object? expected, {String reason = ''}) {
      final m = wrapMatcher(expected);
      final state = <dynamic, dynamic>{};
      if (!m.matches(actual, state)) {
        final d = m.describeMismatch(actual, StringDescription(), state, false);
        failures.add('$reason: expected ${m.describe(StringDescription())}, actual $actual ($d)');
        note('CHECK FAILED $reason: actual $actual');
      }
    }

    final stamp = find.byKey(const ValueKey('receiptVoidedStamp'));
    String newestSaleId() {
      final sales = [...(c.read(salesProvider).value ?? const [])]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sales.first.id;
    }

    Future<String?> tapAndReadSnack(String label) async {
      await tapText(tester, label);
      final end = DateTime.now().add(const Duration(seconds: 15));
      while (find.byType(SnackBar).evaluate().isEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final s = find.descendant(of: find.byType(SnackBar), matching: find.byType(Text));
      return s.evaluate().isEmpty ? null : (s.evaluate().first.widget as Text).data;
    }

    Future<void> saveAndShareOnReceiptScreen(String tag) async {
      await hostCmd(tester, 'photos');
      final msg = await tapAndReadSnack(receiptSaveText);
      note('$tag save: snackbar "$msg"');
      await hostCmd(tester, 'photos');
      check(msg, receiptSavedText);
      await wait(tester, const Duration(seconds: 4));
      await tapText(tester, receiptShareText);
      await wait(tester, const Duration(seconds: 4));
      note('$tag share tapped: failed message shown=${find.text(receiptShareFailedText).evaluate().isNotEmpty}');
      check(find.text(receiptShareFailedText), findsNothing);
      await shot(tester, 'r14_bug45_${tag}_share_sheet');
      await hostCmd(tester, 'apptmp');
    }

    switch (step) {
      case 'valid':
        app.router.go(Routes.pos);
        await settle(tester);
        if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
        await tapText(tester, soap);
        await tapText(tester, 'ငွေရှင်းမယ်');
        await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
        await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
        final id = newestSaleId();
        note('valid sale $id voided=${c.read(saleByIdProvider(id)).value?.voided} route ${app.router.location}');
        note('valid receipt screen: stamp widgets=${stamp.evaluate().length}');
        check(stamp, findsNothing);
        await shot(tester, 'r14_bug45_valid_receipt_screen');
        await saveAndShareOnReceiptScreen('valid');
      case 'void_detail':
        final id = newestSaleId();
        app.router.go(Routes.sale(id));
        await settle(tester);
        await waitFor(tester, find.text('ပယ်ဖျက်မယ်'), why: 'sale screen, not voided yet');
        await tapText(tester, 'ပယ်ဖျက်မယ်');
        await waitFor(tester, find.text('ပယ်ဖျက်ပြီး'), why: 'voided badge');
        note('sale $id voided=${c.read(saleByIdProvider(id)).value?.voided}');
        await shot(tester, 'r14_bug45_voided_sale_screen');
        await tapText(tester, receiptShareText);
        await wait(tester, const Duration(seconds: 4));
        note('void_detail share tapped: failed message shown=${find.text(receiptShareFailedText).evaluate().isNotEmpty}');
        check(find.text(receiptShareFailedText), findsNothing);
        await shot(tester, 'r14_bug45_void_detail_share_sheet');
        await hostCmd(tester, 'apptmp');
      case 'void_receipt':
        final id = newestSaleId();
        c.listen(saleByIdProvider(id), (_, _) {});
        await wait(tester, const Duration(seconds: 1));
        note('newest sale $id voided=${c.read(saleByIdProvider(id)).value?.voided}');
        check(c.read(saleByIdProvider(id)).value?.voided, isTrue, reason: 'run void_detail first');
        app.router.go(Routes.receipt(id));
        await settle(tester);
        await waitFor(tester, find.text(receiptSaveText), why: 'receipt screen');
        note('voided receipt screen: stamp widgets=${stamp.evaluate().length}');
        await shot(tester, 'r14_bug45_voided_receipt_screen');
        await saveAndShareOnReceiptScreen('void_receipt');
    }
    note('layout/framework problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    FlutterError.onError = old;
    expect(problems, isEmpty);
    expect(failures, isEmpty);
  });
}
