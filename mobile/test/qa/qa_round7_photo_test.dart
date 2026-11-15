// QA round 7 — product photos (beta-polish 6e94350).
//
// Spec lines used (6e94350 commit / hand-over):
// - "Add/Edit Product photo square (productPhotoButton, preview productPhotoPreview) → 'ဓာတ်ပုံ ရိုက်မယ် / ပုံ ရွေးမယ် /
//   ဓာတ်ပုံ ဖယ်မယ်' via photoPickerProvider."
// - "compressPhoto (package:image): EXIF orientation, longest side ≤ 1024, JPEG ≤ 200 KB."
// - "Stored locally only (DiskPhotoFiles: <documents>/product_photos/<id>.jpg); not synced. Shown on POS tiles and the
//   Products list (key productPhoto), broken file → initial."
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/features/products/data/product_photos.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

/// Hard-to-compress noise.
img.Image _noise(int w, int h, {int seed = 7}) {
  final r = Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return im;
}

/// Left half red, right half blue (to see where a rotation put each half).
img.Image _halves(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    if (p.x < w ~/ 2) {
      p
        ..r = 255
        ..g = 0
        ..b = 0;
    } else {
      p
        ..r = 0
        ..g = 0
        ..b = 255;
    }
  }
  return im;
}

bool _red(img.Pixel p) => p.r > 180 && p.b < 80;
bool _blue(img.Pixel p) => p.b > 180 && p.r < 80;

class _Picker implements PhotoPicker {
  Uint8List? next;
  final sources = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    sources.add(source);
    return next;
  }
}

void main() {
  setUpAll(loadAppFonts);

  // ================================================================ TC-PROD-NEW-30 compressPhoto
  group('TC-PROD-NEW-30 compressPhoto', () {
    test('12 MP camera JPEG (4032×3024 noise, q95) → JPEG ≤ 200 KB, longest side ≤ 1024, aspect kept', () {
      final raw = img.encodeJpg(_noise(4032, 3024), quality: 95);
      expect(raw.length, greaterThan(2 * 1024 * 1024), reason: 'precondition: a big input');
      final out = compressPhoto(raw);
      expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
      expect(out.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG');
      final back = img.decodeJpg(out)!;
      expect(max(back.width, back.height), lessThanOrEqualTo(1024));
      expect((back.width / back.height - 4032 / 3024).abs(), lessThan(0.02), reason: '${back.width}×${back.height}');
    });

    test('EXIF orientation 6 / 8 / 3 is applied to the pixels and not left in the output (no double rotation)', () {
      for (final (o, w, h, topLeftRed) in [(6, 200, 400, true), (8, 200, 400, false), (3, 400, 200, false)]) {
        final src = _halves(400, 200)..exif.imageIfd.orientation = o;
        final raw = img.encodeJpg(src, quality: 95);
        // precondition: the input carries an EXIF block (package:image applies + clears the orientation while decoding,
        // so it cannot be read back through decodeJpg).
        expect(String.fromCharCodes(raw.sublist(0, 200)).contains('Exif'), isTrue, reason: 'precondition: EXIF $o written');
        final out = img.decodeJpg(compressPhoto(raw))!;
        expect((out.width, out.height), (w, h), reason: 'orientation $o');
        final left = out.exif.imageIfd.hasOrientation ? out.exif.imageIfd.orientation : 1;
        expect(left, 1, reason: 'orientation $o: the output must not ask the viewer to rotate again');
        final tl = out.getPixel(5, 5), br = out.getPixel(out.width - 6, out.height - 6);
        expect((_red(tl), _blue(br)), (topLeftRed, topLeftRed),
            reason: 'orientation $o: top-left ${tl.r},${tl.g},${tl.b}; bottom-right ${br.r},${br.g},${br.b}');
        expect((_blue(tl), _red(br)), (!topLeftRed, !topLeftRed), reason: 'orientation $o');
      }
    });

    test('panorama 6000×60 and 60×6000, PNG with transparency, 1×1 → all JPEG ≤ 200 KB, longest ≤ 1024, ≥ 1 px', () {
      for (final im in [_noise(6000, 60), _noise(60, 6000), img.Image(width: 1, height: 1)]) {
        final out = img.decodeJpg(compressPhoto(img.encodePng(im)))!;
        expect(max(out.width, out.height), lessThanOrEqualTo(1024));
        expect(min(out.width, out.height), greaterThanOrEqualTo(1));
      }
      final alpha = img.Image(width: 300, height: 300, numChannels: 4);
      for (final p in alpha) {
        p.a = p.x < 150 ? 0 : 255;
      }
      final out = compressPhoto(img.encodePng(alpha));
      expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
      expect(img.decodeJpg(out)!.width, 300);
    });

    test('a cut-off JPEG and random bytes do not hang: error or a valid ≤ 200 KB JPEG', () {
      final full = img.encodeJpg(_noise(800, 600), quality: 90);
      for (final bad in [Uint8List.sublistView(full, 0, full.length ~/ 2), Uint8List.fromList(List.generate(5000, (i) => i * 7 % 256))]) {
        try {
          final out = compressPhoto(bad);
          expect(out.length, lessThanOrEqualTo(maxPhotoBytes));
          expect(img.decodeJpg(out), isNotNull);
        } on Object catch (e) {
          expect(e, isNot(isA<StackOverflowError>()));
        }
      }
    });
  });

  // ================================================================ TC-PROD-NEW-31 photo in the forms, lists and on disk
  group('TC-PROD-NEW-31 photo: take / pick / replace / remove / broken / missing', () {
    Future<(ProviderContainer, _Picker, MemoryPhotoFiles)> boot(WidgetTester tester, {PhotoFiles? files}) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final picker = _Picker();
      final base = ProviderContainer(overrides: [...fakeRepositoryOverrides, photoPickerProvider.overrideWithValue(picker)]);
      addTearDown(base.dispose);
      // fakeRepositoryOverrides already binds MemoryPhotoFiles: a child container swaps in the real disk store.
      // (productPhotosProvider is re-created in the child so it reads the child's store; the POS grid watches it.)
      final c = files == null
          ? base
          : ProviderContainer(parent: base, overrides: [
              photoFilesProvider.overrideWithValue(files),
              productPhotosProvider.overrideWith(ProductPhotos.new),
            ]);
      if (files != null) addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      final mem = files == null ? c.read(photoFilesProvider) as MemoryPhotoFiles : MemoryPhotoFiles();
      return (c, picker, mem);
    }

    FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);
    Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
    final photoKey = find.byKey(const ValueKey('productPhoto'));
    final preview = find.byKey(const ValueKey('productPhotoPreview'));

    Future<void> choose(WidgetTester tester, String option) async {
      await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('သိမ်းမယ်').last);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();
    }

    Future<void> editSeedWater(WidgetTester tester, ProviderContainer c) async {
      final water = db(c).products.firstWhere((p) => p.name == 'ရေသန့် 1L');
      c.read(appRouterProvider).go(Routes.editProduct(water.id));
      await tester.pumpAndSettle();
    }

    String waterId(ProviderContainer c) => db(c).products.firstWhere((p) => p.name == 'ရေသန့် 1L').id;

    testWidgets('new form: "ဓာတ်ပုံ ရိုက်မယ်" uses the camera; a cancelled camera changes nothing; no "ဖယ်မယ်" without a '
        'photo; a refused save stores nothing, the next good save stores ONE photo under the new product id', (tester) async {
      final (c, picker, files) = await boot(tester);
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
      await tester.pumpAndSettle();
      expect(find.text('ဓာတ်ပုံ ဖယ်မယ်'), findsNothing);
      await tester.tap(find.text('ဓာတ်ပုံ ရိုက်မယ်'));
      await tester.pumpAndSettle();
      expect(picker.sources, [PhotoSource.camera]);
      expect(preview, findsNothing, reason: 'camera cancelled');

      picker.next = img.encodePng(_noise(300, 200));
      await choose(tester, 'ဓာတ်ပုံ ရိုက်မယ်');
      expect(preview, findsOneWidget);
      await tester.enterText(field('price'), '800');
      await save(tester); // no name → refused
      expect(find.text('ပစ္စည်းအသစ်'), findsOneWidget, reason: 'still on the form');
      expect(files.bytes, isEmpty, reason: 'nothing stored for a product that was not saved');

      await tester.enterText(field('productName'), 'QA R7 photo new');
      await save(tester);
      final p = db(c).products.singleWhere((x) => x.name == 'QA R7 photo new');
      expect(files.bytes.keys, [p.id]);
      expect(img.decodeJpg(files.bytes[p.id]!)!.width, 300);
    });

    testWidgets('edit: replace A with B → B stored (one file); remove + back without saving keeps B; remove then pick C → '
        'C stored; a plain price edit leaves the photo bytes untouched', (tester) async {
      final (c, picker, files) = await boot(tester);
      final id = waterId(c);
      await tester.runAsync(() => c.read(productPhotosProvider.notifier).save(id, img.encodePng(_noise(64, 64))));
      await tester.pumpAndSettle();

      await editSeedWater(tester, c);
      expect(preview, findsOneWidget);
      picker.next = img.encodePng(_noise(120, 80, seed: 2));
      await choose(tester, 'ပုံ ရွေးမယ်');
      await save(tester);
      expect(files.bytes.keys, [id]);
      expect(img.decodeJpg(files.bytes[id]!)!.width, 120, reason: 'B replaced A');

      await editSeedWater(tester, c);
      await choose(tester, 'ဓာတ်ပုံ ဖယ်မယ်');
      expect(preview, findsNothing);
      c.read(appRouterProvider).go(Routes.products); // leave without saving
      await tester.pumpAndSettle();
      expect(img.decodeJpg(files.bytes[id]!)!.width, 120, reason: 'remove not saved → photo kept');

      await editSeedWater(tester, c);
      await choose(tester, 'ဓာတ်ပုံ ဖယ်မယ်');
      picker.next = img.encodePng(_noise(90, 90, seed: 3));
      await choose(tester, 'ပုံ ရွေးမယ်');
      await save(tester);
      expect(img.decodeJpg(files.bytes[id]!)!.width, 90, reason: 'remove then pick = the new photo');

      final before = files.bytes[id];
      await editSeedWater(tester, c);
      await tester.enterText(field('price'), '650');
      await save(tester);
      expect(identical(files.bytes[id], before), isTrue, reason: 'photo not rewritten by a price edit');
      expect(db(c).products.firstWhere((p) => p.id == id).price, 650);
    });

    testWidgets('picked file is not an image → the product is still saved, "ဓာတ်ပုံ သိမ်းလို့ မရပါ", no photo stored',
        (tester) async {
      final (c, picker, files) = await boot(tester);
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      picker.next = Uint8List.fromList(List.filled(400, 7));
      await choose(tester, 'ပုံ ရွေးမယ်');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      // The preview is an Image without errorBuilder: keep what it reported and judge it at the end.
      final previewError = tester.takeException();
      await tester.enterText(field('productName'), 'QA R7 bad photo');
      await tester.enterText(field('price'), '800');
      await save(tester);
      expect(db(c).products.where((x) => x.name == 'QA R7 bad photo'), hasLength(1));
      expect(find.text('ဓာတ်ပုံ သိမ်းလို့ မရပါ'), findsOneWidget);
      expect(files.bytes, isEmpty);
      expect(previewError, isNull,
          reason: 'the form preview of an unreadable picked file must fall back (camera box) like the tiles do, '
              'not raise an image error');
    });

    testWidgets('broken photo file → Products list, POS tile and the edit form show the initial / camera box, no error',
        (tester) async {
      final (c, _, files) = await boot(tester);
      final id = waterId(c);
      files.bytes[id] = Uint8List.fromList(List.filled(300, 1));
      c.invalidate(productPhotosProvider);
      await tester.pumpAndSettle();

      // Edit form first (the image is not cached yet, so its own error handling is what shows).
      await editSeedWater(tester, c);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final formError = tester.takeException();
      c.read(appRouterProvider).go(Routes.products);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'ရေသန့်');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.descendant(of: photoKey, matching: find.text('ရ')), findsOneWidget, reason: 'Products list: initial');

      c.read(appRouterProvider).go(Routes.pos);
      await tester.pumpAndSettle();
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
        await tester.tap(find.text('ပစ္စည်းများ'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(EditableText).first, 'ရေသန့်');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.descendant(of: photoKey, matching: find.text('ရ')), findsOneWidget, reason: 'POS tile: initial');
      expect(tester.takeException(), isNull, reason: 'tiles / list handle the broken file');
      expect(formError, isNull, reason: 'edit form with a broken saved photo: falls back, no image error');
    });

    testWidgets('on disk: replace keeps one file; a file deleted behind the app, a corrupt .jpg and non-photo files → '
        'initial on the POS tile, only *.jpg loaded', (tester) async {
      final tmp = (await tester.runAsync(() => Directory.systemTemp.createTemp('qa_r7_photos_')))!;
      addTearDown(() => tmp.deleteSync(recursive: true));
      final disk = DiskPhotoFiles(root: () async => tmp);
      final dir = Directory('${tmp.path}/product_photos');
      await tester.runAsync(() async {
        await disk.write('a', compressPhoto(img.encodePng(_noise(50, 50))));
        await disk.write('a', compressPhoto(img.encodePng(_noise(70, 70))));
        File('${dir.path}/b.jpg').writeAsBytesSync(List.filled(100, 3)); // corrupt
        File('${dir.path}/notes.txt').writeAsStringSync('x');
        Directory('${dir.path}/c.jpg').createSync(); // a folder named like a photo
      });
      final all = (await tester.runAsync(disk.loadAll))!;
      expect(all.keys.toSet(), {'a', 'b'});
      expect(img.decodeJpg(File('${dir.path}/a.jpg').readAsBytesSync())!.width, 70, reason: 'replaced in place');

      final (c, _, _) = await boot(tester, files: disk);
      final id = waterId(c);
      await tester.runAsync(() async {
        await disk.write(id, compressPhoto(img.encodePng(_noise(40, 40))));
      });
      c.invalidate(productPhotosProvider);
      await tester.runAsync(() => c.read(productPhotosProvider.future));
      File('${dir.path}/$id.jpg').deleteSync(); // gone behind the app (e.g. storage cleaned)
      c.read(appRouterProvider).go(Routes.pos);
      await tester.pumpAndSettle();
      if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
        await tester.tap(find.text('ပစ္စည်းများ'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(EditableText).first, 'ရေသန့်');
      expect(c.read(productPhotosProvider).value?[id], isNotNull, reason: 'precondition: listed before the file went');
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.descendant(of: photoKey, matching: find.text('ရ')), findsOneWidget,
          reason: 'missing file → initial (photo widgets: ${photoKey.evaluate().length}, "ရ": ${find.text('ရ').evaluate().length})');
      expect(tester.takeException(), isNull);
    });
  });
}
