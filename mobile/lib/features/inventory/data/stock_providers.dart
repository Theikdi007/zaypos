import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/stock_movement.dart';
import 'stock_repository.dart';

/// The stock ledger (live).
final stockMovementsProvider =
    StreamProvider<List<StockMovement>>((ref) => ref.watch(stockRepositoryProvider).watchAll());
