// QA round 13 — TC-UX-NEW-10 (new): buttons that look ready must do something visible (BUG-40 fixed the receipt buttons;
// this checks the same pattern elsewhere). A tap counts as "did something" if the route changes or a dialog, bottom sheet,
// snackbar or new overlay route appears. Each probe prints what happened; the test fails listing the dead ones.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-UX-NEW-10 visible buttons are not dead (debt call / Viber reminder, contact picker, Excel, transfer photo)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      // Control only: Photos saving without the platform plugin.
      receiptOutletProvider.overrideWithValue(_SavedOutlet()),
      receiptRendererProvider.overrideWithValue((_, _, _) async => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final router = c.read(appRouterProvider);
    String loc() => router.state.matchedLocation;
    int overlays() =>
        find.byType(Dialog).evaluate().length +
        find.byType(BottomSheet).evaluate().length +
        find.byType(SnackBar).evaluate().length +
        find.byType(ModalBarrier).evaluate().length;

    final dead = <String>[];
    Future<void> probe(String name, String route, Finder Function() target, {Future<void> Function()? before}) async {
      router.go(route);
      await tester.pumpAndSettle();
      if (before != null) await before();
      final t = target();
      expect(t, findsWidgets, reason: '$name is on screen');
      await tester.ensureVisible(t.first);
      await tester.pumpAndSettle();
      final l0 = loc(), o0 = overlays();
      await tester.tap(t.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      final l1 = loc(), o1 = overlays();
      final did = l1 != l0 || o1 > o0;
      // ignore: avoid_print
      print('TC-UX-NEW-10 $name: route $l0 → $l1, overlays $o0 → $o1 → ${did ? 'reacts' : 'NOTHING'}');
      if (!did) dead.add(name);
      if (o1 > o0) {
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    }

    // Positive control: the fixed receipt button reacts ("သိမ်းပြီးပါပြီ" snackbar).
    await probe('CONTROL receipt "ပုံ သိမ်းမယ်"', Routes.receipt(SeedIds.sale1032), () => find.text('ပုံ သိမ်းမယ်'));
    expect(dead, isEmpty, reason: 'the probe must see a reacting button');

    await probe('debt screen "ဖုန်းခေါ်ရန်"', Routes.customer(SeedIds.zawMin),
        () => find.bySemanticsLabel('ဖုန်းခေါ်ရန်'));
    await probe('debt screen "Viber သတိပေး"', Routes.customer(SeedIds.zawMin), () => find.text('Viber သတိပေး'));
    await probe('add customer "ဖုန်းစာအုပ်ထဲက ရွေးရန်"', Routes.addCustomer, () => find.descendant(
            of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'ဖုန်းစာအုပ်ထဲက ရွေးရန်'),
            matching: find.byType(InkWell)));
    await probe('reports "Excel"', Routes.reports, () => find.text('Excel'));
    await probe('checkout KBZPay "ငွေလွှဲပြေစာ ပုံ"', Routes.checkout, () {
      return find.descendant(
          of: find.ancestor(of: find.text('ငွေလွှဲပြေစာ ပုံ (မဖြစ်မနေ မဟုတ်ပါ)'), matching: find.byType(Column)).first,
          matching: find.byType(InkWell));
    }, before: () async {
      final p = (await tester.runAsync(() => val(c, productsProvider)))!.first.product;
      c.read(cartProvider.notifier).addProduct(p);
      router.go(Routes.checkout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('KBZPay').first);
      await tester.pumpAndSettle();
    });

    expect(dead, isEmpty, reason: 'buttons that do nothing: $dead');
  });
}

class _SavedOutlet implements ReceiptOutlet {
  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async {}

  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async => ReceiptSaveResult.saved;
}
