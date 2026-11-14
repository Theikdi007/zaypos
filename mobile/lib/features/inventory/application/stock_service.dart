import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../../auth/data/session.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product_modules.dart';
import '../data/stock_repository.dart';
import '../domain/stock_movement.dart';

/// Goods received and count corrections, each ONE unit of work
/// (restock / stockAdjust).
class StockService {
  StockService({required this.uow, required this.tenantId, required this.stock, required this.products});

  final UnitOfWork uow;
  final String tenantId;
  final StockRepository stock;
  final ProductRepository products;

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

  /// Goods received for a module product (BUG-12), ONE restock unit:
  /// - IMEIs: [serials] become in-stock IMEI rows and stock grows by their count;
  /// - batch: into the existing [batchId], or into [newBatch] (created here);
  /// - size/colour: into [variantId].
  Future<StockMovement> receive({
    required String productId,
    required int qtyMilli,
    String? variantId,
    String? batchId,
    ProductBatch? newBatch,
    List<String> serials = const [],
  }) {
    if (qtyMilli <= 0) throw ArgumentError.value(qtyMilli, 'qtyMilli', 'must be positive');
    if (serials.isNotEmpty && qtyMilli != Qty.units(serials.length)) {
      throw ArgumentError.value(qtyMilli, 'qtyMilli', 'must equal the number of IMEIs');
    }
    if (newBatch != null && (batchId != null || newBatch.productId != productId)) {
      throw ArgumentError.value(newBatch, 'newBatch', 'one batch, of this product');
    }
    final t = nowUtc();
    final m = restockMovement(
      tenantId: tenantId,
      productId: productId,
      qtyMilli: qtyMilli,
      variantId: variantId,
      batchId: newBatch?.id ?? batchId,
    );
    return uow.run(UnitKind.restock, () async {
      await products.addModules(
        batches: [?newBatch],
        serials: [
          for (final s in serials)
            ProductSerial(
              id: newId(),
              tenantId: tenantId,
              productId: productId,
              serial: s,
              status: SerialStatus.inStock,
              createdAt: t,
              updatedAt: t,
            ),
        ],
      );
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
      products: ref.watch(productRepositoryProvider),
    ));
