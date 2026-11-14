import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/async_combine.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import '../domain/product_view.dart';
import 'product_repository.dart';

/// Catalog master data (live).
final catalogProvider = StreamProvider<List<Product>>((ref) => ref.watch(productRepositoryProvider).watchAll());

/// One live product (edit form).
final productByIdProvider =
    StreamProvider.family<Product?, String>((ref, id) => ref.watch(productRepositoryProvider).watchById(id));

/// A product's module rows (edit form lists them).
final productVariantsProvider = StreamProvider.family<List<ProductVariant>, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchVariants(id));
final productBatchesProvider = StreamProvider.family<List<ProductBatch>, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchBatches(id));
final productSerialsProvider = StreamProvider.family<List<ProductSerial>, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchSerials(id));

/// In-stock IMEIs on this phone (any product): a new IMEI must not be one of them (a sold one may come back: trade-in).
final knownSerialsProvider =
    StreamProvider<Set<String>>((ref) => ref.watch(productRepositoryProvider).watchInStockSerialValues());

/// Stock on hand per variant id (SUM of live movements).
final variantStockProvider = StreamProvider<Map<String, int>>((ref) => ref.watch(stockRepositoryProvider).watchAll().map(
      (moves) {
        final out = <String, int>{};
        for (final m in moves) {
          final v = m.variantId;
          if (v == null || m.deletedAt != null) continue;
          out[v] = (out[v] ?? 0) + m.qtyMilli;
        }
        return out;
      },
    ));

/// Stock on hand + tracked flag per product (over the stock ledger, computed by the database).
final stockByProductProvider =
    StreamProvider<Map<String, StockLevel>>((ref) => ref.watch(stockRepositoryProvider).watchStockByProduct());

/// Products with stock on hand computed from the stock ledger (read model).
final productsProvider = Provider<AsyncValue<List<ProductView>>>((ref) => combineAsync(
      ref.watch(catalogProvider),
      ref.watch(stockByProductProvider),
      (List<Product> products, Map<String, StockLevel> stock) => [
        for (final p in products)
          ProductView(p, stock[p.id]?.onHandMilli ?? 0, stockTracked: stock[p.id]?.tracked ?? false),
      ],
    ));
