import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';
import '../domain/product_modules.dart';

abstract interface class ProductRepository {
  /// Live (not soft-deleted) products.
  List<Product> list();
  List<ProductVariant> variantsOf(String productId);
  List<ProductBatch> batchesOf(String productId);
  List<ProductSerial> serialsOf(String productId);

  /// Saves a product together with its module rows.
  void add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  });
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final productRepositoryProvider = Provider<ProductRepository>(
  (_) => throw UnimplementedError('productRepositoryProvider must be overridden'),
);
