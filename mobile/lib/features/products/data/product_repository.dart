import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';

abstract interface class ProductRepository {
  /// Live (not soft-deleted) products.
  List<Product> list();
  List<ProductVariant> variantsOf(String productId);
  void add(Product product, {List<ProductVariant> variants = const []});
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final productRepositoryProvider = Provider<ProductRepository>(
  (_) => throw UnimplementedError('productRepositoryProvider must be overridden'),
);
