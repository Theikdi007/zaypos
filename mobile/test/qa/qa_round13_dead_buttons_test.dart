// QA round 13 — TC-UX-NEW-10 (new): buttons that look ready must do something visible (BUG-40 fixed the receipt buttons;
// this checks the same pattern elsewhere). A tap counts as "did something" if the route changes, a dialog, bottom sheet,
// snackbar or new overlay route appears, or the set of texts on screen changes. Each probe prints what happened; the test
// fails listing the dead ones.
//
// Round 14 (3f89623, BUG-46 fix): the expected result says "reacts … or is hidden". The contact picker, Reports "Excel" and
// the checkout KBZPay/WavePay screenshot box are hidden now, so they are checked as ABSENT (and nothing tappable took their
// place). Sales history "ယနေ့" must not be a tap target at all. The debtor's call / Viber buttons run the REAL
// PlatformDebtOutlet: the plugin's reply (here: MissingPluginException, no platform in a widget test) arrives on real
// time, so the probe waits with tester.runAsync. The fake clock alone printed "NOTHING" in round 14's first run although the
// handler ran (developer note in BUG-46; QA re-checked: with runAsync the Burmese failure snackbars appear). What the
// buttons do on a real platform (tel: URL, share text) is checked on the simulator: integration_test/qa/r14_debt_actions_test.dart.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/common.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-UX-NEW-10 visible buttons are not dead (debt call / Viber reminder react; contact picker, Excel, transfer '
      'photo hidden; sales "ယနေ့" not tappable)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      // Control only: Photos saving without the platform plugin. The debt outlet is NOT overridden (real plugin path).
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
    Set<String> texts() => {
          for (final e in find.byType(Text).evaluate())
            if ((e.widget as Text).data case final String s) s,
        };
    Future<void> clearSnacks() async {
      for (final s in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
        s.clearSnackBars();
      }
      await tester.pumpAndSettle();
    }

    final dead = <String>[];
    final seen = <String, Set<String>>{};
    Future<void> probe(String name, String route, Finder Function() target, {Future<void> Function()? before}) async {
      router.go(route);
      await tester.pumpAndSettle();
      await clearSnacks();
      if (before != null) await before();
      final t = target();
      expect(t, findsWidgets, reason: '$name is on screen');
      await tester.ensureVisible(t.first);
      await tester.pumpAndSettle();
      final l0 = loc(), o0 = overlays(), t0 = texts();
      await tester.tap(t.first, warnIfMissed: false);
      // Platform-channel replies (url_launcher / share_plus) need real time, not the fake clock.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final l1 = loc(), o1 = overlays(), t1 = texts();
      final newTexts = t1.difference(t0);
      final did = l1 != l0 || o1 > o0 || newTexts.isNotEmpty;
      seen[name] = newTexts;
      // ignore: avoid_print
      print('TC-UX-NEW-10 $name: route $l0 → $l1, overlays $o0 → $o1, new texts $newTexts → ${did ? 'reacts' : 'NOTHING'}');
      if (!did) dead.add(name);
      if (o1 > o0) {
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    }

    // Positive control: the fixed receipt button reacts ("သိမ်းပြီးပါပြီ" snackbar).
    await probe('CONTROL receipt "ပုံ သိမ်းမယ်"', Routes.receipt(SeedIds.sale1032), () => find.text('ပုံ သိမ်းမယ်'));
    expect(dead, isEmpty, reason: 'the probe must see a reacting button');

    // 1-2: the debtor's buttons now run the real platform path. In a widget test there is no plugin, so the visible
    // reaction is the Burmese failure message: proof that the tap reaches launchUrl / share and is not an empty handler.
    await probe('debt screen "ဖုန်းခေါ်ရန်"', Routes.customer(SeedIds.zawMin), () => find.bySemanticsLabel(debtCallLabel));
    await probe('debt screen "Viber သတိပေး"', Routes.customer(SeedIds.zawMin), () => find.text(debtRemindLabel));
    expect(seen['debt screen "ဖုန်းခေါ်ရန်"'], contains(debtCallFailedText));
    expect(seen['debt screen "Viber သတိပေး"'], contains(debtRemindFailedText));
    expect(dead, isEmpty, reason: 'buttons that do nothing: $dead');

    // 3-5: hidden for the beta ("or is hidden").
    final handle = tester.ensureSemantics();
    router.go(Routes.addCustomer);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('ဖုန်းစာအုပ်ထဲက ရွေးရန်'), findsNothing, reason: 'contact picker hidden');
    expect(find.byWidgetPredicate((w) => w is AppInput && w.semanticLabel == 'ဖုန်းနံပါတ်'), findsOneWidget,
        reason: 'the phone field itself stays');
    // Layout around the removed picker: the phone field now spans the same width as the name field above it.
    final nameBox = tester.getRect(find.byWidgetPredicate((w) => w is AppInput && w.semanticLabel == 'အမည်'));
    final phoneBox = tester.getRect(find.byWidgetPredicate((w) => w is AppInput && w.semanticLabel == 'ဖုန်းနံပါတ်'));
    // ignore: avoid_print
    print('TC-UX-NEW-10 add customer: name field $nameBox, phone field $phoneBox');
    expect(phoneBox.left, nameBox.left);
    expect(phoneBox.right, nameBox.right);

    router.go(Routes.reports);
    await tester.pumpAndSettle();
    expect(find.text('Excel'), findsNothing, reason: 'Reports "Excel" hidden');

    final p = (await tester.runAsync(() => val(c, productsProvider)))!.first.product;
    c.read(cartProvider.notifier).addProduct(p);
    for (final method in ['KBZPay', 'WavePay']) {
      router.go(Routes.checkout);
      await tester.pumpAndSettle();
      await tester.tap(find.text(method).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('ငွေလွှဲပြေစာ ပုံ'), findsNothing, reason: '$method screenshot box hidden');
      expect(find.text('+ ဓာတ်ပုံ ထည့်မယ်'), findsNothing, reason: '$method screenshot box hidden');
      expect(tester.takeException(), isNull);
    }

    // 6: sales history "ယနေ့" is a label: no tap handler above it and not announced as a button.
    router.go(Routes.sales);
    await tester.pumpAndSettle();
    final today = find.text('ယနေ့').first;
    final tappableAbove = find.ancestor(
        of: today, matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null || w is InkWell && w.onTap != null));
    expect(tappableAbove, findsNothing, reason: '"ယနေ့" must not be a tap target');
    final node = tester.getSemantics(today);
    expect(node.flagsCollection.isButton, isFalse, reason: '"ယနေ့" must not be announced as a button');
    handle.dispose();
  });
}

class _SavedOutlet implements ReceiptOutlet {
  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async {}

  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async => ReceiptSaveResult.saved;
}
