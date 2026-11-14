// QA round 1 — sync behaviour of the app (in-memory Drift + fake sync API):
// TC-SYNC-02 and TC-SYNC-NEW-1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show drive, settle;

void main() {
  setUpAll(loadAppFonts);

  // ---------------------------------------------------------------- TC-SYNC-02
  testWidgets('TC-SYNC-02 offline: 3 sales → chip "Offline · sync ၃ ခုစောင့်"; online → pushed in order, "Sync ပြီး"',
      (tester) async {
    final db = memoryDb();
    addTearDown(() => tester.runAsync(db.close));
    final api = FakeSyncApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(db, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    expect(find.text('Sync ပြီး'), findsOneWidget);

    // Airplane mode: every push fails with a network error.
    for (var i = 0; i < 10; i++) {
      api.pushErrors.add(const ApiError.network());
    }
    final water = draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(1), price: 600, cost: 450);
    final nos = <String>[];
    for (var i = 0; i < 3; i++) {
      nos.add((await drive(tester, () => sell(c, [water]))).no);
    }
    await drive(tester, () => Future<void>.delayed(const Duration(seconds: 3))); // debounced sync → network error
    expect(find.text('Offline · sync ၃ ခုစောင့်'), findsOneWidget);

    // Back online.
    api.pushErrors.clear();
    final pushesBefore = api.pushes.length;
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));

    final sent = api.pushes.skip(pushesBefore).expand((p) => p).toList();
    expect(sent.map((u) => u.kind), ['checkout', 'checkout', 'checkout']);
    expect(sent.map((u) => (u.rows[WireTable.sales] as List).single['no']), nos, reason: 'oldest first');
    expect(find.text('Sync ပြီး'), findsOneWidget);
    expect(await tester.runAsync(() => outbox(db)), isEmpty);
  });

  // ---------------------------------------------------------------- TC-SYNC-NEW-1
  // README §3.3: the server clamps a future UpdatedAt to serverTime + 5 min. Phone A (clock 1 h ahead)
  // keeps its UNclamped local updatedAt; phone B edits the same product 10 min later (real time) and
  // WINS on the server (B > clamped A). A then pulls B's row — and must show it (TC-SYNC-06: the
  // later edit wins on BOTH devices).
  test('TC-SYNC-NEW-1 after a clock-skewed edit, a later edit from another phone still reaches the skewed phone',
      () async {
    final db = memoryDb();
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final store = SyncStore(db, tenantId: shop.tenantId, deviceId: shop.deviceId);
    await store.markInitialSyncDone();
    final api = FakeSyncApi();
    final realNow = DateTime.now().toUtc();
    final engine = SyncEngine(api: api, store: store, deviceId: shop.deviceId, clock: () => realNow);

    // Phone A's clock is 1 hour ahead when the owner renames the product.
    final skewed = realNow.add(const Duration(hours: 1));
    final p = Product(
      id: newId(), tenantId: shop.tenantId, name: 'A (clock +1h)', cost: 100, price: 150, category: 'General',
      tint: 0xFFE0F2F1, initial: 'A', createdAt: skewed, updatedAt: skewed,
    );
    await c.read(productServiceProvider).create(p);
    await engine.syncNow(manual: true); // applied (server stored updatedAt = now + 5 min, clockSkew issue)

    // Phone B (correct clock) edits it 10 minutes later; the server takes it (now+10 min > now+5 min).
    final bAt = realNow.add(const Duration(minutes: 10));
    final bRow = {
      ...productWire((await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle())),
      'name': 'B (later, correct clock)',
      'updatedAt': bAt.toIso8601String(),
    };
    api.pages.add(page({WireTable.products: [bRow]}, cursor: '00000000000000A1'));
    await engine.syncNow(manual: true);

    final local = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
    expect(local.name, 'B (later, correct clock)',
        reason: 'server and phone B show B\'s name; phone A keeps its own (future) edit for the next hour');
  });
}
