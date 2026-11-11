import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';
import 'product_repository.dart';

/// Reactive product list for the UI (depends only on [ProductRepository]).
class ProductsNotifier extends Notifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  List<Product> build() => _repo.list();

  void add(Product p, {List<ProductVariant> variants = const []}) {
    _repo.add(p, variants: variants);
    state = _repo.list();
  }

  void adjustStock(String id, int deltaMilli) {
    _repo.adjustStock(id, deltaMilli);
    state = _repo.list();
  }
}

final productsProvider = NotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);
