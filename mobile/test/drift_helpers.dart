import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session_store.dart';

/// In-memory Drift database (no files, no network).
AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// The signed-in shop of a Drift test container.
class TestShop {
  const TestShop({required this.tenantId, required this.deviceId, required this.store});
  final String tenantId;
  final String deviceId;
  final MemorySecureStore store;
}

const testPhone = '+959700000001';

/// A stored session for [tenantId] (tokens are placeholders).
StoredSession testSession(String tenantId, {String pinHash = 'x'}) => StoredSession(
      tenantId: tenantId,
      userId: newId(),
      deviceCode: 'A',
      phone: testPhone,
      shopName: 'Test shop',
      templateId: 'grocery',
      role: 'owner',
      accessToken: 'access',
      accessExpiresAt: DateTime.utc(2100),
      refreshToken: 'refresh',
      pinHash: pinHash,
    );

/// Container wired like the app (Drift composition root) over [db], already
/// signed in and unlocked as a shop that owns the local data. [seed] fills
/// it with the sample shop (device A, last receipt A-1032).
Future<(ProviderContainer, TestShop)> driftContainer(
  AppDatabase db, {
  bool seed = true,
  List<Override> overrides = const [],
  MemorySecureStore? store,
}) async {
  // Same database + same secure store = same install (same device id).
  store ??= MemorySecureStore();
  final boot = await bootstrap(db, store);
  final local = LocalData(db);
  var owner = await local.owner();
  if (owner == null) {
    final tenantId = newId();
    await local.adopt(
      tenantId: tenantId,
      phone: testPhone,
      shopName: 'Test shop',
      templateId: 'grocery',
      deviceId: boot.deviceId,
      deviceCode: 'A',
      deviceLastSeq: seed ? 1032 : 0,
    );
    if (seed) await seedSampleShop(db, tenantId: tenantId, deviceId: boot.deviceId, releaseMode: false);
    owner = await local.owner();
  }
  final unlocked = BootState(deviceId: boot.deviceId, session: testSession(owner!.tenantId), startUnlocked: true);
  final c = ProviderContainer(overrides: [...driftOverrides(db, unlocked, store), ...overrides]);
  return (c, TestShop(tenantId: owner.tenantId, deviceId: boot.deviceId, store: store));
}

/// Waits until [p] has data (Drift streams resolve asynchronously).
Future<T> settled<T>(ProviderContainer c, ProviderListenable<AsyncValue<T>> p) async {
  final sub = c.listen<AsyncValue<T>>(p, (_, _) {});
  try {
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final v = sub.read();
      if (v.hasError) throw v.error!;
      if (v.hasValue && !v.isLoading) return v.requireValue;
    }
    throw StateError('provider never settled');
  } finally {
    sub.close();
  }
}

/// Outbox rows in push order.
Future<List<OutboxRow>> outbox(AppDatabase db) =>
    (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

Map<String, dynamic> rowsOf(OutboxRow o) => jsonDecode(o.rowsJson) as Map<String, dynamic>;
