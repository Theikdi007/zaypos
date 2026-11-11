import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/stock_movement.dart';

/// Append-only stock ledger. There is no "set stock" — only movements.
abstract interface class StockRepository {
  /// Live movements, all products.
  List<StockMovement> list();
  void addAll(List<StockMovement> movements);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final stockRepositoryProvider = Provider<StockRepository>(
  (_) => throw UnimplementedError('stockRepositoryProvider must be overridden'),
);
