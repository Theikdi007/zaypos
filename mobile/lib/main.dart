import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/drift_overrides.dart';
import 'core/db/app_database.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_store.dart';
import 'core/sync/sync_lifecycle.dart';
import 'core/sync/sync_limits.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/boot_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline-first: fonts are bundled assets, never fetched at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  final db = AppDatabase(driftDatabase(name: 'zaypos'));
  const store = FlutterSecureStore();
  final boot = await bootstrap(db, store);
  final limits = await loadLimits(db);
  runApp(ProviderScope(
    overrides: [...driftOverrides(db, boot, store), initialLimitsProvider.overrideWithValue(limits)],
    child: const ZayPosApp(),
  ));
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
      builder: (_, child) => SyncLifecycle(child: child ?? const SizedBox()),
    );
  }
}
