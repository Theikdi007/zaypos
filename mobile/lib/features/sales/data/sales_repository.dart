import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sale.dart';

abstract interface class SalesRepository {
  /// Live sales, newest first.
  Stream<List<Sale>> watchAll();
  Stream<Sale?> watchById(String id);
  Future<void> add(Sale sale);
  Future<void> setVoided(String id, bool voided);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final salesRepositoryProvider = Provider<SalesRepository>(
  (_) => throw UnimplementedError('salesRepositoryProvider must be overridden'),
);
