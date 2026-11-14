import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/products/data/product_photos.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// A noisy image (hard to compress) as PNG bytes.
Uint8List noisyPng(int w, int h, {int seed = 1}) {
  final r = Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return img.encodePng(im);
}

class FakePhotoPicker implements PhotoPicker {
  Uint8List? next;
  PhotoSource? lastSource;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    lastSource = source;
    return next;
  }
}

/// Product photos (beta-polish item 2): ≤ 200 KB JPEG, stored on this phone,
/// shown on POS tiles and in the Products list.
void main() {
  setUpAll(loadAppFonts);

  group('compressPhoto', () {
    test('a large noisy photo becomes a JPEG ≤ 200 KB, longest side ≤ 1024', () {
      final raw = noisyPng(2400, 1600);
      expect(raw.length, greaterThan(maxPhotoBytes * 5));
      final out = compressPhoto(raw);
      expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
      final back = img.decodeJpg(out)!;
      expect(back.width > back.height, isTrue, reason: 'aspect kept (landscape)');
      expect(max(back.width, back.height), lessThanOrEqualTo(1024));
    });

    test('portrait keeps its orientation; a small photo is not enlarged', () {
      final p = img.decodeJpg(compressPhoto(noisyPng(600, 1800)))!;
      expect(p.height > p.width, isTrue);
      final s = img.decodeJpg(compressPhoto(noisyPng(120, 80)))!;
      expect((s.width, s.height), (120, 80));
    });

    test('not an image → FormatException', () {
      expect(() => compressPhoto(Uint8List.fromList(List.filled(100, 7))), throwsFormatException);
    });
  });

  test('DiskPhotoFiles: write → loadAll finds it; delete removes it; a missing folder is no error', () async {
    final tmp = await Directory.systemTemp.createTemp('zaypos_photos_');
    addTearDown(() => tmp.delete(recursive: true));
    final files = DiskPhotoFiles(root: () async => tmp);
    expect(await files.loadAll(), isEmpty);
    await files.write('p1', compressPhoto(noisyPng(50, 50)));
    final all = await files.loadAll();
    expect(all.keys, ['p1']);
    expect(File('${tmp.path}/product_photos/p1.jpg').lengthSync(), lessThanOrEqualTo(maxPhotoBytes));
    await files.delete('p1');
    expect(await files.loadAll(), isEmpty);
    final broken = DiskPhotoFiles(root: () async => throw const FileSystemException('no storage'));
    expect(await broken.loadAll(), isEmpty);
  });

  Future<(ProviderContainer, FakePhotoPicker, MemoryPhotoFiles)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picker = FakePhotoPicker();
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      photoPickerProvider.overrideWithValue(picker),
    ]);
    addTearDown(c.dispose);
    final files = c.read(photoFilesProvider) as MemoryPhotoFiles; // the fakes keep photos in memory
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (c, picker, files);
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));

  testWidgets('Add Product: pick a photo → preview → save → ≤ 200 KB stored; shown on the POS tile and in Products',
      (tester) async {
    final (c, picker, files) = await boot(tester);
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    picker.next = await tester.runAsync(() async => noisyPng(1600, 1200));
    await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပုံ ရွေးမယ်'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, PhotoSource.gallery);
    expect(find.byKey(const ValueKey('productPhotoPreview')), findsOneWidget);

    await tester.enterText(field('productName'), 'QA photo soap');
    await tester.enterText(field('price'), '800');
    await tester.runAsync(() async {
      await tester.tap(find.text('သိမ်းမယ်').last);
      await Future<void>.delayed(const Duration(seconds: 2)); // compression of the noisy image
    });
    await tester.pumpAndSettle();

    expect(files.bytes, hasLength(1));
    expect(files.bytes.values.single.length, lessThanOrEqualTo(maxPhotoBytes));

    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'QA photo soap');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('productPhoto')), findsOneWidget, reason: 'Products list shows the photo');

    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(EditableText).first, 'QA photo soap');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('productPhoto')), findsOneWidget, reason: 'POS tile shows the photo');
  });

  testWidgets('Edit Product: an existing photo is shown and can be removed; products without one show the initial',
      (tester) async {
    final (c, _, files) = await boot(tester);
    final products = c.read(fakeDatabaseProvider).products;
    final p = products.first;
    await c.read(productPhotosProvider.notifier).save(p.id, await tester.runAsync(() async => noisyPng(64, 64)) as Uint8List);
    await tester.pumpAndSettle();

    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('productPhoto')), findsOneWidget, reason: 'only the one product has a photo');

    c.read(appRouterProvider).go(Routes.editProduct(p.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('productPhotoPreview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ဓာတ်ပုံ ဖယ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('productPhotoPreview')), findsNothing);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    expect(files.bytes, isEmpty);
    expect(c.read(productPhotoProvider(p.id)), isNull);
  });
}
