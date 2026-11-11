import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/async_combine.dart';
import '../../inventory/data/stock_providers.dart';
import '../../inventory/domain/stock_movement.dart';
import '../domain/product.dart';
import '../domain/product_view.dart';
import 'product_repository.dart';

/// Catalog master data (live).
final catalogProvider = StreamProvider<List<Product>>((ref) => ref.watch(productRepositoryProvider).watchAll());

/// Products with stock on hand computed from the stock ledger (read model).
final productsProvider = Provider<AsyncValue<List<ProductView>>>((ref) => combineAsync(
      ref.watch(catalogProvider),
      ref.watch(stockMovementsProvider),
      (List<Product> products, List<StockMovement> moves) {
        final stock = stockByProduct(moves);
        return [for (final p in products) ProductView(p, stock[p.id] ?? 0)];
      },
    ));
