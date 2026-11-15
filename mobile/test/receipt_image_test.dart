// BUG-40: the receipt buttons render the receipt to a PNG and share it / save it to Photos.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

class FakeOutlet implements ReceiptOutlet {
  ReceiptSaveResult saveResult = ReceiptSaveResult.saved;
  final shared = <(Uint8List, String)>[];
  final saved = <(Uint8List, String)>[];

  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async => shared.add((png, fileName));

  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async {
    saved.add((png, name));
    return saveResult;
  }
}

final _fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

void main() {
  setUpAll(loadAppFonts);

  Future<(ProviderContainer, FakeOutlet, List<Sale>)> boot(WidgetTester tester,
      {ReceiptRenderer? renderer}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outlet = FakeOutlet();
    final rendered = <Sale>[];
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      receiptOutletProvider.overrideWithValue(outlet),
      receiptRendererProvider.overrideWithValue(renderer ??
          (view, sale, shop) async {
            rendered.add(sale);
            return _fakePng;
          }),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, outlet, rendered);
  }

  Future<void> open(WidgetTester tester, ProviderContainer c, String route) async {
    c.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
  }

  group('receipt screen', () {
    final route = '/sales/${SeedIds.sale1032}/receipt';

    testWidgets('labels: "ပြေစာ ပို့မယ်" replaces "Viber ပို့မယ်"; "ပုံ သိမ်းမယ်" stays', (tester) async {
      final (c, _, _) = await boot(tester);
      await open(tester, c, route);
      expect(find.text('ပြေစာ ပို့မယ်'), findsOneWidget);
      expect(find.text('ပုံ သိမ်းမယ်'), findsOneWidget);
      expect(find.textContaining('Viber'), findsNothing);
    });

    testWidgets('"ပြေစာ ပို့မယ်" renders this sale and opens the share sheet with the PNG', (tester) async {
      final (c, outlet, rendered) = await boot(tester);
      await open(tester, c, route);
      await tester.tap(find.text('ပြေစာ ပို့မယ်'));
      await tester.pumpAndSettle();
      expect(rendered.single.id, SeedIds.sale1032);
      expect(outlet.shared, hasLength(1));
      expect(outlet.shared.single.$1, _fakePng);
      expect(outlet.shared.single.$2, 'ZayPOS-receipt-${rendered.single.no}.png');
      expect(outlet.saved, isEmpty);
    });

    testWidgets('"ပုံ သိမ်းမယ်" saves the PNG to Photos and shows "သိမ်းပြီးပါပြီ"', (tester) async {
      final (c, outlet, _) = await boot(tester);
      await open(tester, c, route);
      await tester.tap(find.text('ပုံ သိမ်းမယ်'));
      await tester.pump();
      expect(outlet.saved.single.$1, _fakePng);
      expect(find.text('သိမ်းပြီးပါပြီ'), findsOneWidget);
    });

    testWidgets('Photos permission denied → Burmese message, nothing claimed saved', (tester) async {
      final (c, outlet, _) = await boot(tester);
      outlet.saveResult = ReceiptSaveResult.denied;
      await open(tester, c, route);
      await tester.tap(find.text('ပုံ သိမ်းမယ်'));
      await tester.pump();
      expect(find.text(receiptSaveDeniedText), findsOneWidget);
      expect(find.text('သိမ်းပြီးပါပြီ'), findsNothing);
    });

    testWidgets('save fails → Burmese failure message', (tester) async {
      final (c, outlet, _) = await boot(tester);
      outlet.saveResult = ReceiptSaveResult.failed;
      await open(tester, c, route);
      await tester.tap(find.text('ပုံ သိမ်းမယ်'));
      await tester.pump();
      expect(find.text(receiptSaveFailedText), findsOneWidget);
    });

    testWidgets('rendering fails → share and save show a Burmese message, no share sheet', (tester) async {
      final (c, outlet, _) = await boot(tester, renderer: (_, _, _) async => throw StateError('boom'));
      await open(tester, c, route);
      await tester.tap(find.text('ပြေစာ ပို့မယ်'));
      await tester.pump();
      expect(find.text(receiptShareFailedText), findsOneWidget);
      expect(outlet.shared, isEmpty);
      await tester.tap(find.text('ပုံ သိမ်းမယ်'));
      await tester.pump();
      expect(find.text(receiptSaveFailedText), findsOneWidget);
      expect(outlet.saved, isEmpty);
    });
  });

  testWidgets('sale screen "ပြေစာ ပို့မယ်" shares that sale\'s receipt PNG', (tester) async {
    final (c, outlet, rendered) = await boot(tester);
    await open(tester, c, '/sales/${SeedIds.sale1030}');
    await tester.tap(find.text('ပြေစာ ပို့မယ်'));
    await tester.pumpAndSettle();
    expect(rendered.single.id, SeedIds.sale1030);
    expect(outlet.shared.single.$1, _fakePng);
  });

  group('renderReceiptPng', () {
    Future<img.Image> renderSeed(WidgetTester tester, String saleId) async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final sale = (await tester.runAsync(() => val(c, saleByIdProvider(saleId))))!;
      final png = (await tester.runAsync(() => renderReceiptPng(tester.view, sale: sale, shop: 'ဇေ စတိုး')))!;
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'PNG signature');
      return img.decodePng(png)!;
    }

    testWidgets('fixed width 360 × 3 = 1080 px, white background, real height', (tester) async {
      final image = await renderSeed(tester, SeedIds.sale1032);
      expect(image.width, (receiptImageWidth * receiptImagePixelRatio).round());
      expect(image.height, greaterThan(600), reason: 'shop, lines, total');
      expect(image.height, lessThan(6000), reason: 'sized to the receipt, not the 20000 px canvas');
      final corner = image.getPixel(2, 2);
      expect([corner.r, corner.g, corner.b, corner.a], [255, 255, 255, 255]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the phone\'s text size does not change the image (no overflow at ×3.12)', (tester) async {
      final normal = await renderSeed(tester, SeedIds.sale1032);
      tester.platformDispatcher.textScaleFactorTestValue = 3.12;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final large = await renderSeed(tester, SeedIds.sale1032);
      expect(large.width, normal.width);
      expect(large.height, normal.height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sale screen\'s view works too (no on-screen receipt needed)', (tester) async {
      final image = await renderSeed(tester, SeedIds.sale1030);
      expect(image.width, 1080);
      expect(ui.PlatformDispatcher.instance.views, isNotEmpty);
    });
  });
}
