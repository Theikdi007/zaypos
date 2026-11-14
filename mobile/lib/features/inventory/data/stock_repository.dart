import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/stock_movement.dart';

/// Append-only stock ledger. There is no "set stock" — only movements.
abstract interface class StockRepository {
  /// Live movements, all products.
  Stream<List<StockMovement>> watchAll();

  /// Stock on hand per product id (milli-units, SUM of live movements) and
  /// whether it is tracked yet (see [startsTracking]). Products without
  /// movements are absent (= [StockLevel.untracked]).
  Stream<Map<String, StockLevel>> watchStockByProduct();

  Future<void> addAll(List<StockMovement> movements);
}

/// Bound at the composition root (lib/app/drift_overrides.dart).
final stockRepositoryProvider = Provider<StockRepository>(
  (_) => throw UnimplementedError('stockRepositoryProvider must be overridden'),
);
