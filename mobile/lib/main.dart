import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/drift_overrides.dart';
import 'app/local_bootstrap.dart';
import 'core/db/app_database.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-first: fonts are bundled assets, never fetched at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  final db = AppDatabase(driftDatabase(name: 'zaypos'));
  final me = await bootstrapLocalDatabase(db, seedSampleData: kDebugMode);
  runApp(ProviderScope(overrides: driftOverrides(db, me), child: const ZayPosApp()));
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
