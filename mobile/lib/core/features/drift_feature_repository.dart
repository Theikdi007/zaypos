import '../data/unit_recorder.dart';
import '../db/app_database.dart';
import '../sync/wire.dart';
import '../utils/ids.dart';
import 'feature_repository.dart';

class DriftFeatureRepository implements FeatureRepository {
  DriftFeatureRepository(this.db, {required this.tenantId});
  final AppDatabase db;
  final String tenantId;

  @override
  Stream<Map<String, bool>> watchAll() =>
      (db.select(db.tenantFeatureFlags)..where((f) => f.tenantId.equals(tenantId)))
          .watch()
          .map((rows) => {for (final r in rows) r.featureKey: r.enabled});

  @override
  Future<void> setAll(Map<String, bool> values) async {
    final rec = UnitRecorder.require();
    final t = nowUtc();
    for (final e in values.entries) {
      final row = TenantFeatureRow(tenantId: tenantId, featureKey: e.key, enabled: e.value, updatedAt: t);
      await db.into(db.tenantFeatureFlags).insertOnConflictUpdate(row);
      rec.record(WireTable.tenantFeatures, tenantFeatureWire(row));
    }
  }
}
