import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/auth/presentation/pin_reset_screen.dart';
import 'package:zaypos_app/features/auth/presentation/unlock_screen.dart';
import 'package:zaypos_app/features/devices/data/devices_api.dart';
import 'package:zaypos_app/features/devices/presentation/devices_screen.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/preset_catalog_api.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'fake_step4_apis.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

void main() {
  final limits = bundledLimits();
  const presets = [
    PresetItem(name: 'ကိုကာကိုလာ 330ml', category: 'အချိုရည်', unit: 'ဘူး', barcode: '၈၈၅၀၉၉၉၃၂၀၀၁၄', suggestedPrice: 800, sortOrder: 1),
    PresetItem(name: 'ဆား', category: '', unit: 'ထုပ်', barcode: 'ကခ', sortOrder: 2),
    PresetItem(name: '  ', category: 'x', unit: '', sortOrder: 3), // blank name: skipped
  ];

  group('presets (§7 register step 3)', () {
    test('productsFromPresets: no prices, default category, barcodes like the server, blank names skipped', () {
      final products = productsFromPresets(presets, tenantId: 't', tint: 0xFFDCFCE7, limits: limits);
      expect(products.map((p) => p.name), ['ကိုကာကိုလာ 330ml', 'ဆား']);
      expect(products.every((p) => p.price == 0 && p.cost == 0), isTrue, reason: 'the owner fills prices');
      expect(products[0].barcode, '8850999320014');
      expect(products[1].barcode, isNull, reason: 'a barcode the server would refuse is dropped, not the product');
      expect(products[1].category, isNotEmpty);
      expect(products.every((p) => p.tint == 0xFFDCFCE7 && p.tenantId == 't'), isTrue);
    });

    late AppDatabase db;
    late FakeAuthApi auth;
    late FakePresetApi presetApi;
    setUp(() {
      db = memoryDb();
      auth = FakeAuthApi();
      presetApi = FakePresetApi(presets);
    });
    tearDown(() => db.close());

    Future<ProviderContainer> launch() async {
      final store = MemorySecureStore();
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, await bootstrap(db, store), store),
        authApiProvider.overrideWithValue(auth),
        presetCatalogApiProvider.overrideWithValue(presetApi),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        initialLimitsProvider.overrideWithValue(limits),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('register with "ကြိုတင်စာရင်း": the presets are ONE upsertProduct unit of the new shop', () async {
      final c = await launch();
      await c.read(authControllerProvider.notifier).register(
          rawPhone: '0971234567', otp: '123456', shopName: 'ကုန်စုံ', templateId: 'grocery', pin: '111111',
          importPresets: true);

      expect(presetApi.fetched, ['grocery']);
      final unit = (await outbox(db)).single;
      expect(unit.kind, 'upsertProduct');
      final rows = SyncStore.rowsOf(unit)[WireTable.products] as List;
      expect(rows.map((r) => r['name']), ['ကိုကာကိုလာ 330ml', 'ဆား']);
      expect(rows.every((r) => r['tenantId'] == auth.tenantId && r['price'] == 0), isTrue);
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(c.read(authControllerProvider).notice, isNull);
    });

    test('a failed preset download does not undo the registration; it leaves a notice', () async {
      presetApi.error = const ApiError.network();
      final c = await launch();
      await c.read(authControllerProvider.notifier).register(
          rawPhone: '0971234567', otp: '123456', shopName: 'ကုန်စုံ', templateId: 'grocery', pin: '111111',
          importPresets: true);
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(c.read(authControllerProvider).notice, contains(AuthMessages.presetsFailed));
      expect(await outbox(db), isEmpty);
    });

    test('without "ကြိုတင်စာရင်း" nothing is downloaded', () async {
      final c = await launch();
      await c.read(authControllerProvider.notifier).register(
          rawPhone: '0971234567', otp: '123456', shopName: 'ကုန်စုံ', templateId: 'grocery', pin: '111111');
      expect(presetApi.fetched, isEmpty);
    });
  });

  group('PIN reset', () {
    late AppDatabase db;
    late MemorySecureStore store;
    late FakeAuthApi auth;
    var now = DateTime.utc(2026, 11, 12, 9);
    setUp(() {
      db = memoryDb();
      store = MemorySecureStore();
      auth = FakeAuthApi();
      now = DateTime.utc(2026, 11, 12, 9);
    });
    tearDown(() => db.close());

    Future<ProviderContainer> launch() async {
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, await bootstrap(db, store), store),
        authApiProvider.overrideWithValue(auth),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        clockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('locked out: SMS code + new PIN → signed in again, new local hash, lockout cleared', () async {
      var c = await launch();
      await c.read(authControllerProvider.notifier).login('0971234567', '123456');
      final oldHash = store.values[SecureKeys.pinHash];
      c = await launch(); // restart: locked
      final ctl = c.read(authControllerProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await expectLater(ctl.unlock('000000'), throwsA(isA<AuthFailure>()));
      }
      expect(await ctl.lockRemaining(), isNotNull);

      await ctl.requestOtp('0971234567', OtpPurpose.reset);
      await ctl.resetPin(rawPhone: '0971234567', otp: '654321', newPin: '246810');

      expect(auth.calls.skip(1), ['otp:reset:+95971234567', 'reset:+95971234567', 'login:+95971234567']);
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(store.values[SecureKeys.pinHash], isNot(oldHash));
      expect(await ctl.lockRemaining(), isNull);
      expect(store.values.containsKey(SecureKeys.pinFailures), isFalse);

      c = await launch(); // the new PIN unlocks offline
      await c.read(authControllerProvider.notifier).unlock('246810');
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
    });

    test('a wrong code: the PIN is not changed and nothing is stored', () async {
      final c = await launch();
      auth.resetError = const ApiError(400, 'otp_invalid');
      await expectLater(
        c.read(authControllerProvider.notifier).resetPin(rawPhone: '0971234567', otp: '000000', newPin: '246810'),
        throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'otp_invalid')),
      );
      expect(auth.calls.where((x) => x.startsWith('login')), isEmpty);
      expect(store.values.containsKey(SecureKeys.pinHash), isFalse);
    });

    test('router: the reset screen is reachable signed out and while locked', () {
      expect(authRedirect(AuthStatus.signedOut, Routes.pinReset), isNull);
      expect(authRedirect(AuthStatus.locked, Routes.pinReset), isNull);
      expect(authRedirect(AuthStatus.locked, Routes.dashboard), Routes.unlock);
    });
  });

  group('screens', () {
    setUpAll(loadAppFonts);

    Future<ProviderContainer> boot(WidgetTester tester, List<Override> overrides, {BootState? state}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [...fakeOverrides(boot: state), ...overrides]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('devices: list with "ဒီဖုန်း"; the owner removes another phone after confirming', (tester) async {
      final api = FakeDevicesApi([remoteDevice('a', 'A', current: true, name: 'iPhone'), remoteDevice('b', 'B', name: 'Android')]);
      final c = await boot(tester, [devicesApiProvider.overrideWithValue(api)]);
      c.read(appRouterProvider).push(Routes.devices);
      await tester.pumpAndSettle();

      expect(find.byType(DevicesScreen), findsOneWidget);
      expect(find.text('ဖုန်း A · iPhone'), findsOneWidget);
      expect(find.text('ဒီဖုန်း'), findsOneWidget);
      expect(find.text('ဖယ်မယ်'), findsOneWidget, reason: 'only the other phone can be removed');

      await tester.tap(find.text('ဖယ်မယ်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('မဖယ်တော့ပါ'));
      await tester.pumpAndSettle();
      expect(api.removed, isEmpty);

      await tester.tap(find.text('ဖယ်မယ်'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ဖယ်မယ်').last);
      await tester.pumpAndSettle();
      expect(api.removed, ['b']);
      expect(find.text('ဖုန်း B · Android'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('devices: offline shows the message and a retry', (tester) async {
      final api = FakeDevicesApi([])..listError = const ApiError.network();
      final c = await boot(tester, [devicesApiProvider.overrideWithValue(api)]);
      c.read(appRouterProvider).push(Routes.devices);
      await tester.pumpAndSettle();
      expect(find.text(apiErrorMessage('network')), findsOneWidget);
      expect(find.text('ပြန်ကြိုးစားမယ်'), findsOneWidget);
    });

    testWidgets('locked out → "PIN မေ့နေပါသလား?" → code + new PIN → the app opens', (tester) async {
      final db = memoryDb();
      addTearDown(() => tester.runAsync(db.close));
      final auth = FakeAuthApi();
      final store = MemorySecureStore();
      final hash = await const PinHasher(iterations: 10, useIsolate: false).hash('123456');
      final session = testSession(auth.tenantId, pinHash: hash);
      store.values.addAll({
        SecureKeys.tenantId: session.tenantId,
        SecureKeys.refreshToken: 'r',
        SecureKeys.pinHash: hash,
        SecureKeys.phone: session.phone,
        SecureKeys.pinLockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
      });
      // The phone already holds this shop (downloaded): the reset keeps the data.
      await tester.runAsync(() async {
        await LocalData(db).adopt(
          tenantId: auth.tenantId,
          phone: session.phone,
          shopName: 'ရွှေဝါ',
          templateId: 'grocery',
          deviceId: 'd',
          deviceCode: 'A',
          deviceLastSeq: 0,
        );
        await db.writeState(SyncStateKeys.initialSyncDone, 'true');
      });
      final c = await boot(tester, [
        appDatabaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(auth),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ], state: BootState(deviceId: newId(), session: session, initialSyncDone: true));
      expect(find.byType(UnlockScreen), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.textContaining('ပိတ်ထားပါတယ်'), findsOneWidget, reason: 'locked out');

      await tester.tap(find.text('PIN မေ့နေပါသလား?'));
      await tester.pumpAndSettle();
      expect(find.byType(PinResetScreen), findsOneWidget);
      expect(find.byType(EditableText).evaluate().map((e) => (e.widget as EditableText).controller.text).first, '9700000001',
          reason: 'the phone of the locked session is prefilled');

      await tester.tap(find.text('ကုဒ်ပို့မယ်'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      final inputs = find.byType(EditableText);
      await tester.enterText(inputs.at(1), '654321');
      await tester.enterText(inputs.at(2), '246810');
      await tester.enterText(inputs.at(3), '246810');
      await tester.tap(find.text('PIN အသစ် သိမ်းမယ်'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }

      expect(auth.calls, ['otp:reset:+959700000001', 'reset:+959700000001', 'login:+959700000001']);
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(find.byType(PinResetScreen), findsNothing);
      expect(c.read(sessionProvider).tenantId, auth.tenantId);
    });
  });
}
