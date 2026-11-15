// BUG-45: a voided sale's receipt image carries a large red "ပယ်ဖျက်ပြီး" stamp, whether it is shared
// ("ပြေစာ ပို့မယ်", sale screen and receipt screen) or saved ("ပုံ သိမ်းမယ်"). A valid sale's receipt has none.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/theme/app_colors.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

class _Outlet implements ReceiptOutlet {
  final shared = <Uint8List>[];
  final saved = <Uint8List>[];

  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async => shared.add(png);

  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async {
    saved.add(png);
    return ReceiptSaveResult.saved;
  }
}

/// Pixels close to the stamp's red (AppColors.danger) in the PNG.
int redPixels(Uint8List png) {
  final image = img.decodePng(png)!;
  final r0 = (AppColors.danger.r * 255).round(), g0 = (AppColors.danger.g * 255).round(), b0 = (AppColors.danger.b * 255).round();
  var n = 0;
  for (final p in image) {
    if ((p.r - r0).abs() < 40 && (p.g - g0).abs() < 40 && (p.b - b0).abs() < 40) n++;
  }
  return n;
}

void main() {
  setUpAll(loadAppFonts);

  Future<(Sale, Sale)> seedSale(WidgetTester tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final sale = (await tester.runAsync(() => val(c, saleByIdProvider(SeedIds.sale1032))))!;
    expect(sale.voided, isFalse);
    return (sale, sale.copyWith(voidedAt: () => DateTime.utc(2026, 11, 15, 12)));
  }

  testWidgets('ReceiptCard: the stamp is on a voided sale only', (tester) async {
    final (valid, voided) = await seedSale(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptCard(sale: valid, shop: 'ဇေ စတိုး'))));
    expect(find.text(receiptVoidedStampText), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptCard(sale: voided, shop: 'ဇေ စတိုး'))));
    expect(find.text(receiptVoidedStampText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the PNG of a voided sale has a large red stamp; the valid one has no red', (tester) async {
    final (valid, voided) = await seedSale(tester);
    final a = (await tester.runAsync(() => renderReceiptPng(tester.view, sale: valid, shop: 'ဇေ စတိုး')))!;
    final b = (await tester.runAsync(() => renderReceiptPng(tester.view, sale: voided, shop: 'ဇေ စတိုး')))!;
    final redA = redPixels(a), redB = redPixels(b);
    final imageB = img.decodePng(b)!;
    // ignore: avoid_print
    print('BUG-45 red pixels valid=$redA voided=$redB of ${imageB.width}×${imageB.height}');
    expect(redA, 0);
    // "Large": at 1080 px wide, the 4 px border and 34 pt text are well over 1% of the image.
    expect(redB, greaterThan(imageB.width * imageB.height ~/ 100));
    expect(imageB.width, 1080, reason: 'same size as a normal receipt');
  });

  Future<(ProviderContainer, _Outlet)> bootVoided(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outlet = _Outlet();
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      // The real renderer (receiptRendererProvider is not replaced), so the stamp is checked in the actual PNG.
      receiptOutletProvider.overrideWithValue(outlet),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    await tester.runAsync(() => c.read(voidSaleServiceProvider).setVoided(SeedIds.sale1032, true));
    await tester.pumpAndSettle();
    return (c, outlet);
  }

  Future<void> tapAndWait(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    // toImage / PNG encoding need real time, not the fake test clock.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('voided sale: share from the sale screen, share and save from the receipt screen all carry the stamp',
      (tester) async {
    final (c, outlet) = await bootVoided(tester);
    final router = c.read(appRouterProvider);

    router.go(Routes.sale(SeedIds.sale1032));
    await tester.pumpAndSettle();
    expect(find.text('ပယ်ဖျက်ပြီး'), findsWidgets, reason: 'the sale screen shows it voided');
    await tapAndWait(tester, receiptShareText);

    router.go(Routes.receipt(SeedIds.sale1032));
    await tester.pumpAndSettle();
    await tapAndWait(tester, receiptShareText);
    await tapAndWait(tester, receiptSaveText);

    expect(outlet.shared, hasLength(2));
    expect(outlet.saved, hasLength(1));
    for (final png in [...outlet.shared, ...outlet.saved]) {
      expect(redPixels(png), greaterThan(10000), reason: 'every image of the voided sale is stamped');
    }
  });
}
