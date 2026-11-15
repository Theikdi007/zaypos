// QA round 12b — phone A (shop from r12b_02): Add Product with photos (TC-PROD-NEW-34, picked bytes injected: a PNG,
// a HEIC file, broken bytes), POS camera scan (TC-POS-NEW-9, scanned text injected), HID scanner burst
// (TC-POS-NEW-10, key events injected), checkout, and the receipt buttons (TC-POS-11).
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_photos.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';

import 'qa_harness.dart';

const fixtures = String.fromEnvironment('QA_FIXTURES');
const code = '8850999320014';

class QueueScanner implements BarcodeScanner {
  final queue = Queue<String?>();
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async => queue.isEmpty ? null : queue.removeFirst();
}

class QueuePicker implements PhotoPicker {
  final queue = Queue<Uint8List?>();
  final sources = <PhotoSource>[];
  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    sources.add(source);
    return queue.isEmpty ? null : queue.removeFirst();
  }
}

Finder keyed(String k) => find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

void main() {
  qaBinding();

  testWidgets('A: products with photos, POS scans, checkout, receipt buttons', (tester) async {
    final scanner = QueueScanner();
    final picker = QueuePicker();
    final app = await launchApp(tester, overrides: [
      barcodeScannerProvider.overrideWithValue(scanner),
      photoPickerProvider.overrideWithValue(picker),
    ]);
    await wait(tester, const Duration(seconds: 2));
    note('start: status=${app.container.read(authControllerProvider).status} route=${app.router.location}');
    await unlockIfLocked(tester, app);
    await signInIfSignedOut(tester, app, '9 790 917 051');
    note('after unlock: status=${app.container.read(authControllerProvider).status} route=${app.router.location}');

    // ---------------------------------------------------------------- TC-PROD-NEW-34 (injected picks)
    Future<void> addProduct(String name, int price, int stock,
        {String? barcode, required Uint8List photo, required String pickLabel, required String shotName}) async {
      app.router.go(Routes.addProduct);
      await settle(tester);
      await waitFor(tester, find.byKey(const ValueKey('productPhotoButton')), why: 'Add Product open');
      picker.queue.add(photo);
      await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
      await settle(tester);
      await tapText(tester, pickLabel);
      await wait(tester, const Duration(seconds: 1));
      final errors = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString());
      await shot(tester, '${shotName}_preview');
      FlutterError.onError = old;
      if (errors.isNotEmpty) note('$shotName preview raised: ${errors.first.split('\n').first}');
      await type(tester, keyed('productName'), name);
      if (barcode != null) await type(tester, keyed('barcode'), barcode);
      await type(tester, keyed('price'), '$price');
      await type(tester, keyed('stockQty'), '$stock');
      await tapText(tester, 'သိမ်းမယ်', last: true);
      await wait(tester, const Duration(seconds: 2));
      final snack = find.text('ဓာတ်ပုံ သိမ်းလို့ မရပါ').evaluate().isNotEmpty;
      note('$shotName saved; "ဓာတ်ပုံ သိမ်းလို့ မရပါ" shown=$snack; route=${app.router.location}');
      await shot(tester, '${shotName}_after_save');
    }

    await addProduct('QA r12b ဆပ်ပြာ', 1000, 10,
        barcode: code, photo: File('$fixtures/photo.png').readAsBytesSync(), pickLabel: 'ပုံ ရွေးမယ်', shotName: 'prod34_png');
    await addProduct('QA r12b HEIC', 500, 5,
        photo: File('$fixtures/photo.heic').readAsBytesSync(), pickLabel: 'ဓာတ်ပုံ ရိုက်မယ်', shotName: 'prod34_heic');
    await addProduct('QA r12b ပုံပျက်', 300, 5,
        photo: File('$fixtures/broken.jpg').readAsBytesSync(), pickLabel: 'ပုံ ရွေးမယ်', shotName: 'prod34_broken');
    expect(picker.sources, [PhotoSource.gallery, PhotoSource.camera, PhotoSource.gallery]);
    app.router.go(Routes.products);
    await settle(tester);
    await wait(tester, const Duration(seconds: 1));
    note('product photos shown in list: ${find.byKey(const ValueKey('productPhoto')).evaluate().length}');
    await shot(tester, 'prod34_products_list');

    // ---------------------------------------------------------------- TC-POS-NEW-9 / -10 (injected scans)
    app.router.go(Routes.pos);
    await settle(tester);
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) await tapText(tester, 'ပစ္စည်းများ');
    Cart cart() => app.container.read(cartProvider);
    final start = cart().lines.length;
    expect(start, 0);

    scanner.queue.add(code);
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await settle(tester);
    expect(cart().lines.single.qtyMilli, 1000, reason: 'camera scan adds the product once');
    await shot(tester, 'pos9_camera_scan_added');

    // HID: the scanner "types" fast into the focused search box and ends with Enter.
    await tester.tap(find.byType(EditableText).first);
    await settle(tester);
    for (final ch in code.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(cart().lines.single.qtyMilli, 2000, reason: 'HID burst adds the same product again');
    note('search box after HID burst: "${fieldText(tester, find.byType(EditableText).first)}"');
    await shot(tester, 'pos10_hid_burst_added');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);

    scanner.queue.add('4712345678901');
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await settle(tester);
    expect(find.text('ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ'), findsOneWidget);
    await shot(tester, 'pos9_unknown_barcode');
    await tapText(tester, 'မလုပ်တော့ပါ');
    expect(cart().lines.single.qtyMilli, 2000);

    // ---------------------------------------------------------------- checkout → receipt (TC-POS-11)
    await tapText(tester, 'ငွေရှင်းမယ်');
    await shot(tester, 'pos_checkout');
    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
    await waitFor(tester, find.text('ရောင်းပြီးပါပြီ'));
    await shot(tester, 'pos11_receipt');
    final receiptRoute = app.router.location;

    for (final (label, name) in [('Viber ပို့မယ်', 'pos11_after_viber_tap'), ('ပုံ သိမ်းမယ်', 'pos11_after_save_image_tap')]) {
      final routesBefore = app.router.location;
      await tapText(tester, label);
      await wait(tester, const Duration(seconds: 2));
      final dialogs = find.byType(BottomSheet).evaluate().length + find.byType(Dialog).evaluate().length +
          find.byType(SnackBar).evaluate().length;
      note('tap "$label": route $routesBefore → ${app.router.location}, in-app sheets/dialogs/snackbars=$dialogs');
      await shot(tester, name);
    }
    note('receipt route: $receiptRoute');
  });
}
