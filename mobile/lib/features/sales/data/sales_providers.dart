import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sale.dart';
import 'sales_repository.dart';

/// A line to be sold (from the cart).
typedef SaleLineDraft = ({
  String? productId,
  String? variantId,
  String? batchId,
  String? serialId,
  String name,
  int qtyMilli,
  int price,
  int cost,
});

/// Read side for sales. Writes go through CheckoutService / VoidSaleService.
class SalesNotifier extends Notifier<List<Sale>> {
  SalesRepository get _repo => ref.read(salesRepositoryProvider);

  @override
  List<Sale> build() => _repo.list();

  /// Re-read after a service committed writes.
  void refresh() => state = _repo.list();
}

final salesProvider = NotifierProvider<SalesNotifier, List<Sale>>(SalesNotifier.new);

final saleByIdProvider = Provider.family<Sale?, String>((ref, id) {
  for (final s in ref.watch(salesProvider)) {
    if (s.id == id) return s;
  }
  return null;
});
