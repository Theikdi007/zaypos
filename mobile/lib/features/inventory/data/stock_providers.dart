import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../../sales/domain/sale.dart';
import '../domain/stock_movement.dart';
import 'stock_repository.dart';

class StockLedgerNotifier extends Notifier<List<StockMovement>> {
  StockRepository get _repo => ref.read(stockRepositoryProvider);

  @override
  List<StockMovement> build() => _repo.list();

  void record(List<StockMovement> movements) {
    if (movements.isEmpty) return;
    _repo.addAll(movements);
    state = _repo.list();
  }

  StockMovement _m(String productId, StockMovementType type, int qtyMilli,
      {String? variantId, String? batchId, String? saleId, String note = ''}) {
    final t = nowUtc();
    return StockMovement(
      id: newId(),
      tenantId: ref.read(tenantIdProvider),
      productId: productId,
      variantId: variantId,
      batchId: batchId,
      type: type,
      qtyMilli: qtyMilli,
      saleId: saleId,
      note: note,
      createdAt: t,
      updatedAt: t,
    );
  }

  /// One movement per catalog line of [sale]. [sign] −1 = goods out.
  List<StockMovement> forSale(Sale sale, StockMovementType type, {required int sign, String note = ''}) => [
        for (final l in sale.lines)
          if (l.productId != null)
            _m(l.productId!, type, sign * l.qtyMilli, saleId: sale.id, note: note),
      ];

  StockMovement restock(String productId, int qtyMilli, {String? variantId, String? batchId, String note = ''}) =>
      _m(productId, StockMovementType.restock, qtyMilli, variantId: variantId, batchId: batchId, note: note);
}

final stockLedgerProvider = NotifierProvider<StockLedgerNotifier, List<StockMovement>>(StockLedgerNotifier.new);
