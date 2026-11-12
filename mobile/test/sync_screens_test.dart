import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/settings/presentation/settings_features_screen.dart';
import 'package:zaypos_app/features/sync/presentation/rejected_unit_screen.dart';
import 'package:zaypos_app/features/sync/presentation/sync_review_screen.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  late AppDatabase db;
  late FakeSyncApi api;
  setUp(() {
    db = memoryDb();
    api = FakeSyncApi();
  });
  tearDown(() => db.close());

  Future<(ProviderContainer, TestShop)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    await tester.runAsync(() => SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    return (c, shop);
  }

  Future<void> addProduct(WidgetTester tester, ProviderContainer c, TestShop shop, String name) {
    final t = nowUtc();
    return drive(
      tester,
      () => c.read(productServiceProvider).create(Product(
            id: newId(),
            tenantId: shop.tenantId,
            name: name,
            cost: 1,
            price: 2,
            category: 'General',
            tint: 0,
            initial: 'P',
            createdAt: t,
            updatedAt: t,
          )),
    );
  }

  Future<void> syncNow(WidgetTester tester, ProviderContainer c) =>
      drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));

  Future<void> addRejectedProduct(WidgetTester tester, ProviderContainer c, TestShop shop, String name) async {
    api.outcome = (_) => UnitOutcome.rejected;
    await addProduct(tester, c, shop, name);
    await syncNow(tester, c);
  }

  testWidgets('chip: synced → sync problem (tap opens စစ်ရန်) → rejected unit → fix and resend', (tester) async {
    final (c, shop) = await boot(tester);
    expect(find.text('Sync ပြီး'), findsOneWidget);

    await addRejectedProduct(tester, c, shop, 'x' * 130);
    expect(find.text('Sync ပြဿနာ (၁)'), findsOneWidget);

    await tester.tap(find.text('Sync ပြဿနာ (၁)'));
    await settle(tester);
    expect(find.byType(SyncReviewScreen), findsOneWidget);
    expect(find.text(api.rejectReason), findsOneWidget);
    expect(find.textContaining('ပစ္စည်းအသစ် · xxx'), findsOneWidget);

    await tester.tap(find.textContaining('ပစ္စည်းအသစ် · xxx'));
    await settle(tester);
    expect(find.byType(RejectedUnitScreen), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'ဆပ်ပြာ');
    await tester.ensureVisible(find.text('Support ကို ပို့မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ပြင်ပြီး ပြန်ပို့မယ်'), findsOneWidget);
    expect(find.text('Support ကို ပို့မယ်'), findsOneWidget);
    expect(find.textContaining('ဖျက်'), findsNothing, reason: 'no delete button');
    api.outcome = (_) => UnitOutcome.applied;
    await tester.ensureVisible(find.text('ပြင်ပြီး ပြန်ပို့မယ်')); // below the edit fields
    await tester.tap(find.text('ပြင်ပြီး ပြန်ပို့မယ်'));
    await settle(tester);

    final pushed = api.pushes.last.single;
    expect((pushed.rows[WireTable.products] as List).single['name'], 'ဆပ်ပြာ');
    expect(await tester.runAsync(() => outbox(db)), isEmpty);
    c.read(appRouterProvider).go(Routes.dashboard);
    await settle(tester);
    expect(find.text('Sync ပြီး'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Support ကို ပို့မယ် copies the unit JSON with the reason', (tester) async {
    final (c, shop) = await boot(tester);
    await addRejectedProduct(tester, c, shop, 'bad');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final seq = (await tester.runAsync(() => outbox(db)))!.single.seq;
    c.read(appRouterProvider).push(Routes.rejectedUnit(seq));
    await settle(tester);

    await tester.ensureVisible(find.text('Support ကို ပို့မယ်'));
    await tester.tap(find.text('Support ကို ပို့မယ်'));
    await settle(tester);

    final j = jsonDecode(copied!) as Map<String, dynamic>;
    expect(j['kind'], 'upsertProduct');
    expect(j['rejectReason'], api.rejectReason);
    expect((j['rows'] as Map)['products'], hasLength(1));
    expect(find.textContaining('Viber'), findsOneWidget);
  });

  testWidgets('offline after a network failure; Settings shows waiting units and syncs now', (tester) async {
    final (c, shop) = await boot(tester);
    api.pushErrors.add(const ApiError.network());
    await addProduct(tester, c, shop, 'p');
    // §5.1: the commit schedules a sync 2 s later; it hits the network error.
    await drive(tester, () => Future<void>.delayed(const Duration(seconds: 3)));
    expect(api.pushes, hasLength(1));
    expect(find.text('Offline · sync ၁ ခုစောင့်'), findsOneWidget);

    c.read(appRouterProvider).push(Routes.settingsFeatures);
    await settle(tester);
    // Scroll the Settings list itself (the default would pick the first
    // Scrollable: the dashboard underneath). The section is built lazily.
    await tester.scrollUntilVisible(
      find.text('ယခု sync လုပ်မယ်'),
      200,
      scrollable: find.descendant(of: find.byType(SettingsFeaturesScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('ပို့ရန်စောင့်: ၁ ခု'), findsOneWidget);
    expect(find.text(apiErrorMessage('network')), findsOneWidget);

    await tester.tap(find.text('ယခု sync လုပ်မယ်'));
    await settle(tester);
    expect(find.text('ပို့ရန်စောင့်: ၀ ခု'), findsOneWidget);
    expect(find.text('စစ်ရန် (၀)'), findsOneWidget);
    expect(api.pushes, hasLength(2));
  });

  testWidgets('pull-to-refresh on the dashboard runs a sync', (tester) async {
    await boot(tester);
    final before = api.pullCursors.length;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await settle(tester);
    expect(api.pullCursors.length, greaterThan(before));
  });
}

/// Alternates real time (Drift) and fake time (timers in the app's zone),
/// then settles the UI.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Runs [action] in the test's (fake-time) zone — like a tap would — and
/// alternates real time (Drift) with fake time (debounce/backoff timers)
/// until it completes. Never await engine work inside `runAsync`: a cycle
/// started by the UI lives in the fake zone and would wait forever.
Future<T> drive<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? value;
  Object? error;
  action().then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done) fail('action never completed');
  if (error != null) throw error!;
  await settle(tester);
  return value as T;
}
