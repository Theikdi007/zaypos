import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/app/local_bootstrap.dart';
import 'package:zaypos_app/core/db/app_database.dart';

/// In-memory Drift database (no files, no network).
AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Container wired like the app (Drift composition root) over [db].
Future<(ProviderContainer, LocalIdentity)> driftContainer(AppDatabase db, {bool seed = true}) async {
  final me = await bootstrapLocalDatabase(db, seedSampleData: seed);
  return (ProviderContainer(overrides: driftOverrides(db, me)), me);
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
