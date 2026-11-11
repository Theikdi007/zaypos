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

/// All sales (live). Writes go through CheckoutService / VoidSaleService.
final salesProvider = StreamProvider<List<Sale>>((ref) => ref.watch(salesRepositoryProvider).watchAll());

final saleByIdProvider =
    StreamProvider.family<Sale?, String>((ref, id) => ref.watch(salesRepositoryProvider).watchById(id));
