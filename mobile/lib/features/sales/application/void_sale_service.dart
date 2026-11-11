import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/utils/ids.dart';
import '../../customers/data/debt_repository.dart';
import '../../customers/domain/debt_entry.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product_modules.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'checkout_service.dart';

/// Voids (or un-voids) a sale as ONE unit of work. Nothing is deleted:
/// the sale is flagged, stock gets compensating movements, serials go back
/// to stock, and a credit sale is reversed with a debt adjustment.
class VoidSaleService {
  VoidSaleService({
    required this.uow,
    required this.sales,
    required this.stock,
    required this.debt,
    required this.products,
    this.onCommitted,
  });

  final UnitOfWork uow;
  final SalesRepository sales;
  final StockRepository stock;
  final DebtRepository debt;
  final ProductRepository products;
  final void Function()? onCommitted;

  /// Sets the sale's voided state. No-op if it is already in that state.
  Future<void> setVoided(String saleId, bool voided) async {
    final sale = sales.byId(saleId);
    if (sale == null) throw StateError('Unknown sale $saleId');
    if (sale.voided == voided) return;

    await uow.run(() async {
      sales.setVoided(sale.id, voided);
      stock.addAll(voided
          ? movementsForSale(sale, StockMovementType.voidReturn, sign: 1)
          : movementsForSale(sale, StockMovementType.sale, sign: -1, note: 'unvoid'));
      for (final l in sale.lines) {
        if (l.serialId == null) continue;
        products.setSerialStatus(
          l.serialId!,
          voided ? SerialStatus.inStock : SerialStatus.sold,
          saleLineId: voided ? null : l.id,
        );
      }
      if (sale.method == PaymentMethod.debt && sale.customerId != null) {
        final t = nowUtc();
        debt.add(DebtEntry(
          id: newId(),
          tenantId: sale.tenantId,
          customerId: sale.customerId!,
          type: DebtEntryType.adjustment,
          amount: voided ? -sale.total : sale.total,
          saleId: sale.id,
          saleNo: sale.no,
          note: voided ? 'void' : 'unvoid',
          createdAt: t,
          updatedAt: t,
        ));
      }
    });
    onCommitted?.call();
  }
}

final voidSaleServiceProvider = Provider<VoidSaleService>((ref) => VoidSaleService(
      uow: ref.read(unitOfWorkProvider),
      sales: ref.read(salesRepositoryProvider),
      stock: ref.read(stockRepositoryProvider),
      debt: ref.read(debtRepositoryProvider),
      products: ref.read(productRepositoryProvider),
      onCommitted: () => refreshSalesReadModels(ref),
    ));
