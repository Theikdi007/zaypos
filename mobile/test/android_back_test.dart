// BUG-51 / BUG-56: Android's system back (key or gesture; the engine sends
// popRoute, which `tester.binding.handlePopRoute()` does here).
// - Register step 2 → step 1, entries kept (also in qa_round15_test.dart).
// - A non-home tab → the home tab (ပင်မ); home → asks before leaving the app.
// - After a sale: receipt → sale → sales list → ပင်မ, never out of the app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/google_auth.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// Records SystemNavigator.pop (= the app leaves to the launcher).
List<String> _recordExit(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

Future<ProviderContainer> _bootShop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
      overrides: [
    ...fakeRepositoryOverrides,
    initialLimitsProvider.overrideWithValue(bundledLimits()),
    otpEnabledProvider.overrideWithValue(true), // BUG-51 is about the SMS OTP register wizard
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
  await tester.pumpAndSettle();
  return c;
}

String _path(ProviderContainer c) => c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

const _exitTitle = 'ZayPOS က ထွက်မလား';

void main() {
  setUpAll(loadAppFonts);

  for (final tab in [Routes.products, Routes.customers, Routes.reports]) {
    testWidgets('BUG-56 back on the $tab tab goes to ပင်မ (not out of the app)', (tester) async {
      final exits = _recordExit(tester);
      final c = await _bootShop(tester);
      c.read(appRouterProvider).go(tab);
      await tester.pumpAndSettle();
      await _back(tester);
      expect(_path(c), Routes.dashboard);
      expect(find.text(_exitTitle), findsNothing, reason: 'no exit question on the way home');
      expect(exits, isNot(contains('SystemNavigator.pop')));
    });
  }

  testWidgets('BUG-56 back on ပင်မ asks first: "မထွက်ပါ" stays, "ထွက်မယ်" leaves', (tester) async {
    final exits = _recordExit(tester);
    final c = await _bootShop(tester);
    await _back(tester);
    expect(find.text(_exitTitle), findsOneWidget);
    await tester.tap(find.text('မထွက်ပါ'));
    await tester.pumpAndSettle();
    expect(_path(c), Routes.dashboard);
    expect(exits, isNot(contains('SystemNavigator.pop')));

    await _back(tester);
    await tester.tap(find.text('ထွက်မယ်'));
    await tester.pumpAndSettle();
    expect(exits, contains('SystemNavigator.pop'));
  });

  testWidgets('BUG-56 back on a screen above a tab still goes back one screen (debtor → customer list)', (tester) async {
    final c = await _bootShop(tester);
    final id = c.read(fakeDatabaseProvider).customers.first.id;
    c.read(appRouterProvider).go(Routes.customers);
    await tester.pumpAndSettle();
    c.read(appRouterProvider).push(Routes.customer(id));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_path(c), Routes.customers);
  });

  testWidgets('BUG-56 after a sale: receipt → sale → sales list → ပင်မ; the app is never left', (tester) async {
    final exits = _recordExit(tester);
    final c = await _bootShop(tester);
    final sale = await tester.runAsync(() => sell(c, [draft(name: 'x', price: 500)]));
    c.read(appRouterProvider).go(Routes.receipt(sale!.id)); // what checkout does
    await tester.pumpAndSettle();
    await _back(tester);
    expect(_path(c), Routes.sale(sale.id));
    await _back(tester);
    expect(_path(c), Routes.sales);
    await _back(tester);
    expect(_path(c), Routes.dashboard);
    expect(exits, isNot(contains('SystemNavigator.pop')));
  });

  group('BUG-51 register wizard', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    testWidgets('back on step 2 → step 1 with the phone kept; back on step 1 → Login', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        ...fakeOverrides(boot: BootState(deviceId: newId())),
        appDatabaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        authApiProvider.overrideWithValue(FakeAuthApi()),
        otpEnabledProvider.overrideWithValue(true),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ဆိုင်အသစ် စာရင်းသွင်းမယ်'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '9 7123 4567');
      await tester.tap(find.text('ကုဒ်ပို့မယ်'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, '123456');
      await tester.pump();
      await tester.tap(find.text('ဆက်သွားမယ်'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(EditableText).first, 'ဆိုင်');
      await tester.pump();
      expect(find.text('အဆင့် 2 / 4'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('အဆင့် 1 / 4'), findsOneWidget);
      expect(find.text('9 7123 4567'), findsOneWidget, reason: 'the phone is kept');
      expect(find.text('123456'), findsOneWidget, reason: 'the code is kept');

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ဝင်မယ်'), findsWidgets, reason: 'step 1 back leaves the wizard (Login)');
      // The resend countdown timer of step 1 ends with the screen.
      await tester.pump(const Duration(seconds: 61));
    });
  });
}
