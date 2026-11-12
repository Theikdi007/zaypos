import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../data/stock_repository.dart';
import '../domain/stock_movement.dart';

/// Goods received and count corrections, each ONE unit of work
/// (restock / stockAdjust).
class StockService {
  StockService({required this.uow, required this.tenantId, required this.stock});

  final UnitOfWork uow;
  final String tenantId;
  final StockRepository stock;

  /// Supplier delivery: +[qtyMilli].
  Future<StockMovement> restock({
    required String productId,
    required int qtyMilli,
    String? variantId,
    String? batchId,
    String note = '',
  }) {
    if (qtyMilli <= 0) throw ArgumentError.value(qtyMilli, 'qtyMilli', 'must be positive');
    final m = restockMovement(
      tenantId: tenantId,
      productId: productId,
      qtyMilli: qtyMilli,
      variantId: variantId,
      batchId: batchId,
      note: note,
    );
    return uow.run(UnitKind.restock, () async {
      await stock.addAll([m]);
      return m;
    });
  }

  /// Count correction: signed [deltaMilli] (counted − on hand).
  Future<StockMovement> adjust({
    required String productId,
    required int deltaMilli,
    String? variantId,
    String? batchId,
    String note = '',
  }) {
    if (deltaMilli == 0) throw ArgumentError.value(deltaMilli, 'deltaMilli', 'must not be zero');
    final t = nowUtc();
    final m = StockMovement(
      id: newId(),
      tenantId: tenantId,
      productId: productId,
      variantId: variantId,
      batchId: batchId,
      type: StockMovementType.adjustment,
      qtyMilli: deltaMilli,
      note: note,
      createdAt: t,
      updatedAt: t,
    );
    return uow.run(UnitKind.stockAdjust, () async {
      await stock.addAll([m]);
      return m;
    });
  }
}

final stockServiceProvider = Provider<StockService>((ref) => StockService(
      uow: ref.watch(unitOfWorkProvider),
      tenantId: ref.watch(tenantIdProvider),
      stock: ref.watch(stockRepositoryProvider),
    ));
