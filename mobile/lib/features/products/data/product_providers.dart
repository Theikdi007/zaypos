import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/stock_providers.dart';
import '../../inventory/domain/stock_movement.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import '../domain/product_view.dart';
import 'product_repository.dart';

/// Catalog (master data only; depends only on [ProductRepository]).
class CatalogNotifier extends Notifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  List<Product> build() => _repo.list();

  void add(
    Product p, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) {
    _repo.add(p, variants: variants, batches: batches, serials: serials);
    state = _repo.list();
  }
}

final catalogProvider = NotifierProvider<CatalogNotifier, List<Product>>(CatalogNotifier.new);

/// Products with stock on hand computed from the stock ledger.
final productsProvider = Provider<List<ProductView>>((ref) {
  final stock = stockByProduct(ref.watch(stockLedgerProvider));
  return [for (final p in ref.watch(catalogProvider)) ProductView(p, stock[p.id] ?? 0)];
});
