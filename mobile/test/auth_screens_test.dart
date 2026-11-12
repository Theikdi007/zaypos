import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:zaypos_app/features/auth/presentation/login_screen.dart';
import 'package:zaypos_app/features/auth/presentation/unlock_screen.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  late AppDatabase db;
  late FakeAuthApi api;
  late MemorySecureStore store;
  setUp(() {
    db = memoryDb();
    api = FakeAuthApi();
    store = MemorySecureStore();
  });
  tearDown(() => db.close());

  /// The app with fake repositories, a real (in-memory) local-data guard
  /// and a fake auth API.
  Future<ProviderContainer> boot(WidgetTester tester, {BootState? state, bool release = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeOverrides(boot: state ?? BootState(deviceId: newId())),
      appDatabaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(api),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      isReleaseBuildProvider.overrideWithValue(release),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  /// Lets Drift (real futures) finish, then settles the UI.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
  }

  /// The [i]-th text field on screen (Login: phone, PIN; Register step 1:
  /// phone, code; step 2: shop name).
  Finder input(int i) => find.byType(EditableText).at(i);

  testWidgets('signed out: the app opens on Login; login opens the dashboard', (tester) async {
    final c = await boot(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(input(0), '9 7123 4567');
    await tester.enterText(input(1), '123456');
    await tester.tap(find.text('ဝင်မယ်'));
    await settle(tester);

    expect(api.calls, ['login:+95971234567']);
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong PIN shows the server message in Burmese and stays on Login', (tester) async {
    await boot(tester);
    api.nextError = const ApiError(401, 'invalid_credentials');
    await tester.enterText(input(0), '0971234567');
    await tester.enterText(input(1), '000000');
    await tester.tap(find.text('ဝင်မယ်'));
    await settle(tester);

    expect(find.text('ဖုန်းနံပါတ် (သို့) PIN မှားနေပါတယ်။'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('register: send code, enter it, name the shop, set a PIN → dashboard', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
    await tester.pumpAndSettle();

    await tester.enterText(input(0), '9 7123 4567');
    await tester.tap(find.text('ကုဒ်ပို့မယ်'));
    await settle(tester);
    expect(api.calls, ['otp:register:+95971234567']);

    await tester.enterText(input(1), '482913');
    await tester.tap(find.text('ဆက်သွားမယ်'));
    await tester.pumpAndSettle();

    // Step 2 needs a shop name.
    await tester.tap(find.text('ဆက်သွားမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ဆိုင်အမည် ထည့်ပါ။'), findsOneWidget);
    await tester.enterText(input(0), 'မြဆေးဆိုင်');
    await tester.tap(find.text('ဆက်သွားမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ဆက်သွားမယ်'));
    await tester.pumpAndSettle();

    for (final d in '135790'.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.text('ဆိုင်ဖွင့်မယ်'));
    await settle(tester);

    expect(api.calls.last, 'register:+95971234567:482913:မြဆေးဆိုင်:grocery');
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored session opens on the PIN pad; the right PIN opens the app', (tester) async {
    final hash = await const PinHasher(iterations: 10, useIsolate: false).hash('246810');
    final c = await boot(tester, state: BootState(deviceId: newId(), session: testSession(newId(), pinHash: hash)));
    store.values[SecureKeys.tenantId] = c.read(bootStateProvider).session!.tenantId;
    store.values[SecureKeys.refreshToken] = 'r';
    store.values[SecureKeys.pinHash] = hash;
    expect(find.byType(UnlockScreen), findsOneWidget);

    for (final d in '111111'.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await settle(tester);
    expect(find.textContaining('PIN မှားနေပါတယ်'), findsOneWidget);

    for (final d in '246810'.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await settle(tester);
    expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('the demo shop button exists only in debug builds', (tester) async {
    await boot(tester);
    expect(find.textContaining('Demo ဆိုင်'), findsOneWidget);
  });

  testWidgets('release build: no demo shop button', (tester) async {
    await boot(tester, release: true);
    expect(find.textContaining('Demo ဆိုင်'), findsNothing);
    expect(find.text('ဝင်မယ်'), findsOneWidget);
  });

  testWidgets('signed out with unpushed units: Login shows the kept-outbox warning', (tester) async {
    final c = await boot(tester, state: BootState(deviceId: newId(), startUnlocked: true));
    await db.into(db.outbox).insert(OutboxCompanion.insert(unitId: newId(), kind: 'checkout', rowsJson: '{}', clientTime: 0));
    await tester.runAsync(() => c.read(authControllerProvider.notifier).signOut());
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(AuthMessages.outboxKept(1)), findsOneWidget);
  });
}
