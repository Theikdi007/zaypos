import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/session.dart';
import '../data/unit_of_work.dart';

/// Stored feature flags of the tenant (server table tenantFeatures). Keys are
/// [FeatureFlag] names, which equal the server's FeatureKeys.
abstract interface class FeatureRepository {
  /// featureKey → enabled. Empty until the flags were first saved/pulled.
  Stream<Map<String, bool>> watchAll();

  /// Upserts [values] (one row per key).
  Future<void> setAll(Map<String, bool> values);
}

/// Bound at the composition root (lib/app/drift_overrides.dart).
final featureRepositoryProvider = Provider<FeatureRepository>(
  (_) => throw UnimplementedError('featureRepositoryProvider must be overridden'),
);

/// Saves flag changes as ONE setFeatures unit of work.
class FeatureService {
  FeatureService({required this.uow, required this.features});
  final UnitOfWork uow;
  final FeatureRepository features;

  Future<void> save(Map<String, bool> values) =>
      values.isEmpty ? Future.value() : uow.run(UnitKind.setFeatures, () => features.setAll(values));
}

final featureServiceProvider = Provider<FeatureService>((ref) {
  ref.watch(tenantIdProvider);
  return FeatureService(uow: ref.read(unitOfWorkProvider), features: ref.read(featureRepositoryProvider));
});
