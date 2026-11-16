import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/drift_overrides.dart';
import 'core/api/api_config.dart';
import 'core/db/app_database.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_store.dart';
import 'core/sync/sync_lifecycle.dart';
import 'core/sync/sync_limits.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/boot_state.dart';
import 'features/pos/data/cart_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // BUG-55: a release build with a non-https API URL refuses to start.
  if (insecureBuildScreen(apiBaseUrl, release: kReleaseMode) case final screen?) {
    runApp(screen);
    return;
  }
  await lockPhonesToPortrait();
  // Offline-first: fonts are bundled assets, never fetched at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  final db = AppDatabase(driftDatabase(name: 'zaypos'));
  const store = FlutterSecureStore();
  final boot = await bootstrap(db, store);
  final limits = await loadLimits(db);
  final cart = await loadOpenCart(db);
  runApp(ProviderScope(
    overrides: [
      ...driftOverrides(db, boot, store),
      initialLimitsProvider.overrideWithValue(limits),
      initialCartProvider.overrideWithValue(CartRestore(cart)),
    ],
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
      // BUG-54: Material / Cupertino built-in texts (date picker, dialogs,
      // text selection) in Burmese.
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(appRouterProvider),
      builder: (_, child) => SyncLifecycle(child: child ?? const SizedBox()),
    );
  }
}

/// The app's only locale: Burmese (Myanmar).
const appLocale = Locale('my');

/// Phones narrower than this (shortest side, dp) are locked to portrait.
const tabletShortestSide = 600.0;

/// BUG-58: phones stay in portrait (POS is unusable sideways); tablets rotate.
Future<void> lockPhonesToPortrait({Size? logicalSize}) {
  final size = logicalSize ?? _logicalSize();
  if (size == null || size.shortestSide >= tabletShortestSide) return Future.value();
  return SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

Size? _logicalSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return null;
  final v = views.first;
  return v.physicalSize / v.devicePixelRatio;
}

/// BUG-55: the screen a release build shows instead of the app when its
/// API_BASE_URL is not https (null when the URL is fine). The message is also
/// printed, so `adb logcat` / the Xcode console shows why.
Widget? insecureBuildScreen(String url, {required bool release}) {
  try {
    checkApiBaseUrl(url, release: release);
    return null;
  } on InsecureApiUrl catch (e) {
    // ignore: avoid_print
    print('ZayPOS: $e');
    return InsecureBuildApp(error: e);
  }
}

class InsecureBuildApp extends StatelessWidget {
  const InsecureBuildApp({super.key, required this.error});
  final InsecureApiUrl error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ZayPOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: appLocale,
        supportedLocales: const [appLocale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ZayPOS ကို ဖွင့်လို့ မရပါ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const Text(
                    'ဒီ ZayPOS ကို လုံခြုံမှုမရှိတဲ့ ဆာဗာလိပ်စာနဲ့ တည်ဆောက်ထားလို့ ဖွင့်မပေးပါ။ '
                    'PIN နဲ့ အရောင်းစာရင်းတွေ မပို့ပါ။ ZayPOS ကို ဆက်သွယ်ပါ။',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    'Release build refused: API_BASE_URL must be https://, got "${error.url}".',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
