import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Product photos (beta-polish item 2): ONE compressed JPEG per product,
/// stored on this phone only (`<documents>/product_photos/<productId>.jpg`).
/// They are not synced yet: another phone of the shop shows the initial.

/// Largest photo kept (bytes).
const maxPhotoBytes = 200 * 1024;

/// Decodes [input] (JPEG / PNG / HEIC-converted …), applies the EXIF
/// orientation, scales the longest side to ≤ [maxSide] and re-encodes as JPEG,
/// lowering quality and then size until it is ≤ [maxBytes]. Pure Dart (runs in
/// an isolate in the app). Throws [FormatException] if [input] is not an image.
Uint8List compressPhoto(Uint8List input, {int maxBytes = maxPhotoBytes, int maxSide = 1024}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('Not an image');
  var image = img.bakeOrientation(decoded);
  int longest(img.Image i) => i.width > i.height ? i.width : i.height;
  if (longest(image) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  while (true) {
    for (final q in const [85, 75, 65, 55, 45]) {
      final out = img.encodeJpg(image, quality: q);
      if (out.length <= maxBytes) return out;
    }
    if (longest(image) <= 160) return img.encodeJpg(image, quality: 40); // tiny already: give up shrinking
    image = img.copyResize(image, width: (image.width * 0.75).round(), interpolation: img.Interpolation.average);
  }
}

/// Where photos are kept. [DiskPhotoFiles] in the app; [MemoryPhotoFiles] in tests.
abstract interface class PhotoFiles {
  /// productId → image. Never throws (a missing folder = no photos).
  Future<Map<String, ImageProvider>> loadAll();
  Future<ImageProvider> write(String productId, Uint8List jpeg);
  Future<void> delete(String productId);
}

class DiskPhotoFiles implements PhotoFiles {
  DiskPhotoFiles({Future<Directory> Function()? root}) : _root = root ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _root;

  Future<Directory> _dir() async {
    final d = Directory('${(await _root()).path}/product_photos');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File _file(Directory d, String id) => File('${d.path}/$id.jpg');

  @override
  Future<Map<String, ImageProvider>> loadAll() async {
    try {
      final d = await _dir();
      return {
        await for (final f in d.list())
          if (f is File && f.path.endsWith('.jpg'))
            f.uri.pathSegments.last.replaceAll('.jpg', ''): FileImage(f),
      };
    } catch (_) {
      return {}; // no storage (e.g. tests without the plugin): no photos
    }
  }

  @override
  Future<ImageProvider> write(String productId, Uint8List jpeg) async {
    final f = _file(await _dir(), productId);
    await f.writeAsBytes(jpeg, flush: true);
    final image = FileImage(f);
    await image.evict(); // the same path may hold an older photo in the cache
    return image;
  }

  @override
  Future<void> delete(String productId) async {
    final f = _file(await _dir(), productId);
    if (await f.exists()) await f.delete();
    await FileImage(f).evict();
  }
}

class MemoryPhotoFiles implements PhotoFiles {
  final bytes = <String, Uint8List>{};

  @override
  Future<Map<String, ImageProvider>> loadAll() async => {for (final e in bytes.entries) e.key: MemoryImage(e.value)};

  @override
  Future<ImageProvider> write(String productId, Uint8List jpeg) async {
    bytes[productId] = jpeg;
    return MemoryImage(jpeg);
  }

  @override
  Future<void> delete(String productId) async => bytes.remove(productId);
}

final photoFilesProvider = Provider<PhotoFiles>((_) => DiskPhotoFiles());

/// productId → photo (only products that have one).
class ProductPhotos extends AsyncNotifier<Map<String, ImageProvider>> {
  @override
  Future<Map<String, ImageProvider>> build() => ref.watch(photoFilesProvider).loadAll();

  /// Compresses [raw] to ≤ 200 KB and keeps it as [productId]'s photo.
  Future<void> save(String productId, Uint8List raw) async {
    final jpeg = await ref.read(photoCompressorProvider)(raw);
    final image = await ref.read(photoFilesProvider).write(productId, jpeg);
    final now = {...(state.value ?? await future)};
    now[productId] = image;
    state = AsyncData(now);
  }

  Future<void> remove(String productId) async {
    await ref.read(photoFilesProvider).delete(productId);
    final now = {...(state.value ?? await future)}..remove(productId);
    state = AsyncData(now);
  }
}

final productPhotosProvider =
    AsyncNotifierProvider<ProductPhotos, Map<String, ImageProvider>>(ProductPhotos.new);

/// One product's photo (null = none / not loaded yet).
final productPhotoProvider =
    Provider.family<ImageProvider?, String>((ref, id) => ref.watch(productPhotosProvider).value?[id]);

/// Compression off the UI thread (an isolate); tests run it inline.
typedef PhotoCompressor = Future<Uint8List> Function(Uint8List raw);
final photoCompressorProvider = Provider<PhotoCompressor>((_) => (raw) => Isolate.run(() => compressPhoto(raw)));

/// Camera or gallery. [ImagePickerPhotoPicker] in the app; a fake in tests.
enum PhotoSource { camera, gallery }

abstract interface class PhotoPicker {
  /// The picked image's bytes, or null if cancelled.
  Future<Uint8List?> pick(PhotoSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final f = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048, // the picker already shrinks huge camera photos; compressPhoto does the rest
      imageQuality: 90,
    );
    return f?.readAsBytes();
  }
}

final photoPickerProvider = Provider<PhotoPicker>((_) => ImagePickerPhotoPicker());
