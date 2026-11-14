import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';
import '../domain/product_modules.dart';

/// Catalog store. Reads are streams (re-emit on change); writes are futures.
abstract interface class ProductRepository {
  /// Live (not soft-deleted) products.
  Stream<List<Product>> watchAll();
  Stream<Product?> watchById(String id);
  Stream<List<ProductVariant>> watchVariants(String productId);
  Stream<List<ProductBatch>> watchBatches(String productId);
  Stream<List<ProductSerial>> watchSerials(String productId);

  /// Saves a product together with its module rows.
  Future<void> add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  });

  /// Sets the selling price (kyats); updatedAt moves to now (last-writer-wins).
  Future<void> setPrice(String productId, int price);

  /// Marks an IMEI/serial sold (with its sale line) or back in stock.
  Future<void> setSerialStatus(String serialId, SerialStatus status, {String? saleLineId});
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final productRepositoryProvider = Provider<ProductRepository>(
  (_) => throw UnimplementedError('productRepositoryProvider must be overridden'),
);
