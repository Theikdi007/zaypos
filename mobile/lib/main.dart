import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/fake_overrides.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  // Offline-first: fonts are bundled assets, never fetched at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(ProviderScope(overrides: fakeRepositoryOverrides, child: const ZayPosApp()));
}

class ZayPosApp extends ConsumerWidget {
  const ZayPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ZayPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
