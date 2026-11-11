import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';

/// Creates a product with its module rows and initial stock as ONE unit of
/// work (product + variants + batches + serials + restock movements).
class ProductService {
  ProductService({required this.uow, required this.products, required this.stock});

  final UnitOfWork uow;
  final ProductRepository products;
  final StockRepository stock;

  Future<void> create(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
    List<StockMovement> initialStock = const [],
  }) {
    for (final m in initialStock) {
      if (m.productId != product.id) throw ArgumentError('Movement for another product');
    }
    return uow.run(() async {
      await products.add(product, variants: variants, batches: batches, serials: serials);
      await stock.addAll(initialStock);
    });
  }
}

final productServiceProvider = Provider<ProductService>((ref) => ProductService(
      uow: ref.read(unitOfWorkProvider),
      products: ref.read(productRepositoryProvider),
      stock: ref.read(stockRepositoryProvider),
    ));
