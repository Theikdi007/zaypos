// QA round 13 — BUG-40 / TC-POS-11 on the iOS simulator (phone A, real app, real share_plus + gal plugins).
// QA_STEP (the host sets the Photos permission with `xcrun simctl privacy` BEFORE each run):
//   save    (photos-add granted): sell → receipt → "ပုံ သိမ်းမယ်" → "သိမ်းပြီးပါပြီ" and the image is in Photos (runner `photos`);
//           then "ပြေစာ ပို့မယ်" → the system share sheet (screenshot; the PNG in the app's tmp, runner `apptmp`). Ends with the sheet open.
//   detail  : the newest sale's screen → "ပြေစာ ပို့မယ်" → share sheet. Ends with the sheet open.
//   voided  : void the newest sale on its screen → "ပြေစာ ပို့မယ်" → share sheet; the image the runner copies shows whether
//           the receipt says it is voided (TC-SALE-NEW-1).
//   denied  (photos-add revoked): newest sale's receipt → "ပုံ သိမ်းမယ်" → the denied message, nothing added to Photos.
//   prompt  (photos-add reset): "ပုံ သိမ်းမယ်" → the iOS permission alert with NSPhotoLibraryAddUsageDescription (screenshot).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';

import 'qa_harness.dart';

const step = String.fromEnvironment('QA_STEP', defaultValue: 'save');
const soap = 'QA r12b ဆပ်ပြာ';

void main() {
  qaBinding();

  testWidgets('BUG-40 receipt share / save on the simulator ($step)', (tester) async {
    final app = await launchApp(tester);
    await unlockIfLocked(tester, app, pin: '222222');
    final c = app.container;
    c.listen(salesProvider, (_, _) {});
    await wait(tester, const Duration(seconds: 2));

    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => problems.add('${d.exceptionAsString().split('\n').first} @ ${app.router.location}');
    addTearDown(() => FlutterError.onError = old);

    String newestSaleId() {
      final sales = [...(c.read(salesProvider).value ?? const [])]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sales.first.id;
    }

    Future<void> openReceiptOfNewest() async {
      app.router.go(Routes.receipt(newestSaleId()));
      await settle(tester);
      await waitFor(tester, find.text(receiptSaveText), why: 'receipt screen');
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

    switch (step) {
      case 'save':
        app.router.go(Routes.pos);
        await settle(tester);
        if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
        await tapText(tester, soap);
        await tapText(tester, 'ငွေရှင်းမယ်');
        await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
        await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
        note('receipt route ${app.router.location}');
        expect(find.text(receiptShareText), findsOneWidget);
        expect(find.text(receiptSaveText), findsOneWidget);
        expect(find.textContaining('Viber'), findsNothing, reason: 'old label gone');
        await shot(tester, 'r13_pos11_receipt');
        await hostCmd(tester, 'photos');
        final msg = await tapAndReadSnack(receiptSaveText);
        note('save (granted): snackbar "$msg"');
        await shot(tester, 'r13_pos11_saved_message');
        await hostCmd(tester, 'photos');
        expect(msg, receiptSavedText);
        await wait(tester, const Duration(seconds: 4)); // snackbar gone
        await tapText(tester, receiptShareText);
        await wait(tester, const Duration(seconds: 4));
        note('share tapped: route ${app.router.location}, snackbars=${find.byType(SnackBar).evaluate().length}');
        expect(find.text(receiptShareFailedText), findsNothing);
        await shot(tester, 'r13_pos11_share_sheet_receipt_screen');
        await hostCmd(tester, 'apptmp');
      case 'detail':
        app.router.go(Routes.sale(newestSaleId()));
        await settle(tester);
        await waitFor(tester, find.text(receiptShareText), why: 'sale screen');
        await shot(tester, 'r13_pos11_sale_detail');
        await tapText(tester, receiptShareText);
        await wait(tester, const Duration(seconds: 4));
        expect(find.text(receiptShareFailedText), findsNothing);
        await shot(tester, 'r13_pos11_share_sheet_sale_detail');
        await hostCmd(tester, 'apptmp');
      case 'voided':
        final id = newestSaleId();
        app.router.go(Routes.sale(id));
        await settle(tester);
        await waitFor(tester, find.text('ပယ်ဖျက်မယ်'), why: 'sale screen, not voided yet');
        await tapText(tester, 'ပယ်ဖျက်မယ်'); // no confirm dialog (SaleDetailScreen._toggleVoid)
        await waitFor(tester, find.text('ပယ်ဖျက်ပြီး'), why: 'voided badge');
        note('sale $id voided=${c.read(saleByIdProvider(id)).value?.voided}');
        await shot(tester, 'r13_sale_new1_voided_detail');
        await tapText(tester, receiptShareText);
        await wait(tester, const Duration(seconds: 4));
        await shot(tester, 'r13_sale_new1_voided_share_sheet');
        await hostCmd(tester, 'apptmp');
      case 'denied':
        await openReceiptOfNewest();
        await hostCmd(tester, 'photos');
        final msg = await tapAndReadSnack(receiptSaveText);
        note('save (denied): snackbar "$msg"');
        await shot(tester, 'r13_pos11_denied_message');
        await hostCmd(tester, 'photos');
        expect(msg, receiptSaveDeniedText);
      case 'prompt':
        await openReceiptOfNewest();
        await tester.tap(find.text(receiptSaveText));
        await wait(tester, const Duration(seconds: 3));
        await shot(tester, 'r13_pos11_permission_prompt');
    }
    note('layout/framework problems: ${problems.isEmpty ? 'none' : problems.toSet()}');
    expect(problems, isEmpty);
  });
}
