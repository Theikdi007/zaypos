import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaypos_app/app/fake_overrides.dart';

/// Container wired exactly like the app (fake repositories).
ProviderContainer makeContainer() => ProviderContainer(overrides: fakeRepositoryOverrides);

/// Loads the bundled fonts so layout tests measure real Myanmar glyphs
/// (the default test font draws every glyph as a full-em square).
Future<void> loadAppFonts() async {
  for (final (family, file) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('NotoSansMyanmar', 'assets/fonts/NotoSansMyanmar-Variable.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}
