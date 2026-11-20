import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
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
      expect(products.every((p) => p.price == 0 && p.cost == null), isTrue, reason: 'the owner fills prices');
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
        otpEnabledProvider.overrideWithValue(true), // the SMS OTP screens (AUTH_OTP_ENABLED)
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

  // PIN reset is Google → new PIN (the SMS reset was removed with phone + PIN sign-in):
  // test/google_auth_test.dart and test/google_auth_screens_test.dart.
  group('PIN reset', () {
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
      final c = ProviderContainer(
          overrides: [...fakeOverrides(boot: state), otpEnabledProvider.overrideWithValue(true), ...overrides]);
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

  });
}
