// QA round 1 — AUTH / PIN / FEAT / PROD flows on the app's screens and controller
// (fake auth API, in-memory Drift or fake repositories, no network).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/widgets/app_switch_tile.dart';
import 'package:zaypos_app/core/widgets/product_tile.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/preset_catalog_api.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_auth_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;

/// The 20 grocery presets the server seeds (backend PresetSeed.cs), as /catalog/presets serves them.
const _serverGroceryPresets = [
  ('ဆန် (ပေါ်ဆန်း)', 'စားသောက်ကုန်', 'ပြည်'), ('ပဲဆီ', 'စားသောက်ကုန်', 'ပိဿာ'), ('သကြား', 'စားသောက်ကုန်', 'ပိဿာ'),
  ('ဆား', 'စားသောက်ကုန်', 'ထုပ်'), ('ကြက်ဥ', 'စားသောက်ကုန်', 'ခု'), ('ကြက်သွန်နီ', 'စားသောက်ကုန်', 'ပိဿာ'),
  ('ကြက်သွန်ဖြူ', 'စားသောက်ကုန်', 'ပိဿာ'), ('ငံပြာရည်', 'စားသောက်ကုန်', 'ဗူး'), ('အချိုမှုန့်', 'စားသောက်ကုန်', 'ထုပ်'),
  ('အသင့်စား ခေါက်ဆွဲ', 'စားသောက်ကုန်', 'ထုပ်'), ('လက်ဖက်ခြောက်', 'စားသောက်ကုန်', 'ထုပ်'), ('ရေသန့် 1L', 'အချိုရည်', 'ဗူး'),
  ('ကော်ဖီမစ် 3 in 1', 'အချိုရည်', 'ထုပ်'), ('အချိုရည် ဗူး', 'အချိုရည်', 'ဗူး'), ('ဆပ်ပြာခဲ', 'အိမ်သုံး', 'ခု'),
  ('ဆပ်ပြာမှုန့်', 'အိမ်သုံး', 'ထုပ်'), ('သွားတိုက်ဆေး', 'အိမ်သုံး', 'ခု'), ('မီးခြစ်', 'အိမ်သုံး', 'ခု'),
  ('ဖယောင်းတိုင်', 'အိမ်သုံး', 'ထုပ်'), ('ဘီစကွတ်', 'မုန့်', 'ထုပ်'),
];

void main() {
  setUpAll(loadAppFonts);

  // ================================================================ signed-out screens (fake auth API)
  group('auth screens', () {
    late AppDatabase db;
    late FakeAuthApi api;
    setUp(() {
      db = memoryDb();
      api = FakeAuthApi();
    });
    tearDown(() => db.close());

    Future<ProviderContainer> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        ...fakeOverrides(boot: BootState(deviceId: newId())),
        appDatabaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        authApiProvider.overrideWithValue(api),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      return c;
    }

    // ---------------------------------------------------------------- TC-AUTH-01 (app half)
    testWidgets('TC-AUTH-01 "ကုဒ်ပို့မယ်" → OTP boxes and a 1:00 resend timer that counts down, then resend works',
        (tester) async {
      await boot(tester);
      await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '9 7123 4567');
      await tester.tap(find.text('ကုဒ်ပို့မယ်'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(api.calls, ['otp:register:+95971234567']);
      expect(find.text('အတည်ပြုကုဒ်'), findsOneWidget, reason: 'the 6 OTP boxes are shown');
      expect(find.text('ပြန်ပို့မယ် (1:00)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('ပြန်ပို့မယ် (0:59)'), findsOneWidget);
      await tester.tap(find.text('ပြန်ပို့မယ် (0:59)'));
      await tester.pump();
      expect(api.calls, hasLength(1), reason: 'resend is disabled while counting');

      await tester.pump(const Duration(seconds: 60));
      expect(find.text('ပြန်ပို့မယ်'), findsOneWidget);
      await tester.tap(find.text('ပြန်ပို့မယ်'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(api.calls, hasLength(2));
      expect(find.text('ပြန်ပို့မယ် (1:00)'), findsOneWidget);
    });

    // ---------------------------------------------------------------- TC-FEAT-NEW-1
    testWidgets('TC-FEAT-NEW-1 register step 2: the v2 restaurant template cannot be chosen', (tester) async {
      final c = await boot(tester);
      c.read(appRouterProvider).go('${Routes.register}?step=2');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'QA ဆိုင်');
      await tester.ensureVisible(find.text('စားသောက် / ကော်ဖီ'));
      await tester.tap(find.text('စားသောက် / ကော်ဖီ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ဆက်သွားမယ်'));
      await tester.pumpAndSettle();
      expect(find.textContaining('စားသောက် / ကော်ဖီ အတွက်'), findsNothing,
          reason: 'restaurant is marked v2 ("soon") and is not switchable in Settings either');
    });

    // ---------------------------------------------------------------- TC-PROD-NEW-2
    // Server truth (backend AccountTests + PresetSeed.cs): grocery = 20 presets, no barcodes; others = 0.
    for (final (template, serverCount) in [('grocery', 20), ('pharmacy', 0), ('phone', 0), ('hardware', 0)]) {
      testWidgets('TC-PROD-NEW-2 register step 3 ($template) only promises the presets the server has ($serverCount)',
          (tester) async {
        final c = await boot(tester);
        c.read(shopTemplateProvider.notifier).select(template);
        c.read(appRouterProvider).go('${Routes.register}?step=3');
        await tester.pumpAndSettle();
        final offer = find.textContaining('ကြိုတင်စာရင်း သုံးမယ်');
        final shown = find.textContaining('မျိုး barcode').evaluate().map((e) => (e.widget as Text).data).join();
        if (serverCount == 0) {
          expect(offer, findsNothing, reason: 'offers "$shown" but GET /catalog/presets?template=$template serves 0 items');
        } else {
          expect(find.textContaining('$serverCount မျိုး'), findsOneWidget,
              reason: 'promises "$shown"; the server seeds $serverCount presets, none with a barcode');
        }
      });
    }
  });

  // ================================================================ controller (Drift + fake auth API)
  group('session', () {
    late AppDatabase db;
    late MemorySecureStore store;
    late FakeAuthApi api;
    var now = DateTime.utc(2026, 11, 14, 9);
    setUp(() {
      db = memoryDb();
      store = MemorySecureStore();
      api = FakeAuthApi();
      now = DateTime.utc(2026, 11, 14, 9);
    });
    tearDown(() => db.close());

    Future<ProviderContainer> launch() async {
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, await bootstrap(db, store), store),
        authApiProvider.overrideWithValue(api),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        clockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    // ---------------------------------------------------------------- TC-AUTH-12 (app half)
    test('TC-AUTH-12 refresh refused as replay (401 invalid_refresh_token) → Login, outbox kept and warned', () async {
      final c = await launch();
      await c.read(authControllerProvider.notifier).login('0971234567', '123456');
      final t = nowUtc();
      await c.read(customerServiceProvider).create(
          Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'x', phone: '', createdAt: t, updatedAt: t));
      api.refreshError = const ApiError(401, 'invalid_refresh_token');

      final token = await c.read(tokenRefresherProvider).refresh();

      expect(token, isNull);
      final s = c.read(authControllerProvider);
      expect(s.status, AuthStatus.signedOut);
      expect(s.notice, contains(AuthMessages.outboxKept(1)));
      expect(await outbox(db), hasLength(1));
    });

    // ---------------------------------------------------------------- TC-PIN-03
    test('TC-PIN-03 after a PIN reset the OLD PIN is refused offline, the new one works, no lockout', () async {
      var c = await launch();
      await c.read(authControllerProvider.notifier).login('0971234567', '123456');
      c = await launch();
      final ctl = c.read(authControllerProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await expectLater(ctl.unlock('000000'), throwsA(isA<AuthFailure>()));
      }
      await ctl.requestOtp('0971234567', OtpPurpose.reset);
      await ctl.resetPin(rawPhone: '0971234567', otp: '654321', newPin: '246810');

      c = await launch(); // restart, offline (no API call expected)
      api.calls.clear();
      final ctl2 = c.read(authControllerProvider.notifier);
      expect(await ctl2.lockRemaining(), isNull);
      await expectLater(ctl2.unlock('123456'),
          throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'pin_wrong')));
      await ctl2.unlock('246810');
      expect(c.read(authControllerProvider).status, AuthStatus.unlocked);
      expect(api.calls, isEmpty);
    });
  });

  // ================================================================ signed-in screens (fake repositories)
  group('shop screens', () {
    Future<ProviderContainer> boot(WidgetTester tester, {bool emptyShop = false}) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = makeContainer();
      addTearDown(c.dispose);
      if (emptyShop) {
        c.read(fakeDatabaseProvider)
          ..products.clear()
          ..stock.clear()
          ..sales.clear();
      }
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      return c;
    }

    // ---------------------------------------------------------------- TC-PROD-01
    testWidgets('TC-PROD-01 new grocery shop with the 20 server presets: unpriced, untracked, Dashboard card 20',
        (tester) async {
      final c = await boot(tester, emptyShop: true);
      final items = [
        for (final (i, (n, cat, unit)) in _serverGroceryPresets.indexed)
          PresetItem(name: n, category: cat, unit: unit, sortOrder: i + 1),
      ];
      await c.read(productServiceProvider).importAll(
          productsFromPresets(items, tenantId: c.read(tenantIdProvider), tint: 0xFFDCFCE7, limits: bundledLimits()));
      await tester.pumpAndSettle();

      expect(find.text('ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း ၂၀ ခု'), findsOneWidget);
      c.read(appRouterProvider).go(Routes.products);
      await tester.pumpAndSettle();
      expect(find.text('ဈေးနှုန်းမရှိ (20)'), findsOneWidget);
      expect(find.text('Stock မမှတ်ရသေး (20)'), findsOneWidget);
      expect(find.text(NeedsPriceBadge.label), findsNWidgets(20));
      expect(find.text(untrackedStockLabel), findsNWidgets(20));
    });

    // ---------------------------------------------------------------- TC-FEAT-02 / TC-FEAT-04
    testWidgets('TC-FEAT-02 Settings toggle "သက်တမ်းကုန်ရက် / Batch" → Add Product shows batch + expiry; TC-FEAT-04 restaurant disabled',
        (tester) async {
      final c = await boot(tester);
      expect(c.read(tenantFeaturesProvider).expiryBatch, isFalse, reason: 'grocery default');
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batchNo')), findsNothing);

      c.read(appRouterProvider).go(Routes.settingsFeatures);
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(AppSwitchTile, 'သက်တမ်းကုန်ရက် / Batch');
      await tester.tap(find.descendant(of: tile, matching: find.byType(AppSwitch)));
      await tester.pumpAndSettle();
      expect(c.read(tenantFeaturesProvider).expiryBatch, isTrue);

      final restaurant = tester.widget<AppSwitchTile>(find.widgetWithText(AppSwitchTile, 'စားပွဲ / Order mode'));
      expect((restaurant.enabled, restaurant.value), (false, false), reason: 'TC-FEAT-04');
      final flagsBefore = c.read(tenantFeaturesProvider);
      await tester.tap(find.descendant(of: find.widgetWithText(AppSwitchTile, 'စားပွဲ / Order mode'), matching: find.byType(AppSwitch)),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(c.read(tenantFeaturesProvider), flagsBefore, reason: 'TC-FEAT-04: tapping the v2 toggle changes nothing');

      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batchNo')), findsOneWidget);
      expect(find.textContaining('သက်တမ်းကုန်ရက်'), findsWidgets);
    });

    // ---------------------------------------------------------------- TC-FEAT-03
    testWidgets('TC-FEAT-03 turning expiryBatch off keeps the batch data and hides the fields; on again shows them',
        (tester) async {
      final c = await boot(tester);
      final f = c.read(tenantFeaturesProvider.notifier);
      f.set(FeatureFlag.expiryBatch, true);
      final t = nowUtc();
      final db = c.read(fakeDatabaseProvider);
      db.batches.add(ProductBatch(
          id: newId(), tenantId: c.read(tenantIdProvider), productId: SeedIds.water, batchNo: 'B1',
          expiryDate: DateTime.utc(2027, 6, 30), qtyMilli: 0, createdAt: t, updatedAt: t));

      f.set(FeatureFlag.expiryBatch, false);
      c.read(appRouterProvider).go(Routes.addProduct);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batchNo')), findsNothing);
      expect(db.batches.where((b) => b.batchNo == 'B1'), hasLength(1), reason: 'data kept');

      f.set(FeatureFlag.expiryBatch, true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batchNo')), findsOneWidget);
      expect(db.batches.where((b) => b.batchNo == 'B1'), hasLength(1));
    });

    // ---------------------------------------------------------------- TC-PROD-NEW-1
    testWidgets('TC-PROD-NEW-1 an existing product can be edited (price / cost / name)', (tester) async {
      final c = await boot(tester);
      c.read(appRouterProvider).go(Routes.products);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'ရေသန့် 1L');
      await tester.pumpAndSettle();

      await tester.longPress(find.text('ရေသန့် 1L').last);
      await tester.pumpAndSettle();
      if (find.text('ရောင်းဈေး (Ks)').evaluate().isEmpty) {
        // Plain tap opens "Stock ဖြည့်မယ်"; close it and look for an edit action there or on the row.
        await tester.tap(find.text('ရေသန့် 1L').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('ရောင်းဈေး (Ks)'), findsOneWidget,
          reason: 'no edit screen: a price change (inflation) or a typo cannot be fixed after saving');
    });
  });
}
