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
  });

  final UnitOfWork uow;
  final SalesRepository sales;
  final StockRepository stock;
  final DebtRepository debt;
  final ProductRepository products;

  /// Sets the sale's voided state. No-op if it is already in that state.
  Future<void> setVoided(String saleId, bool voided) async {
    final sale = await sales.watchById(saleId).first;
    if (sale == null) throw StateError('Unknown sale $saleId');
    if (sale.voided == voided) return;

    // BUG-23: a phone of this sale that was already taken back (trade-in: its
    // IMEI is in stock again as a newer row) is not returned a second time —
    // its old row stays as history and no +1 is written for it.
    // BUG-24: "taken back" = a NEWER row with the same IMEI exists (on any
    // product), whatever its status now — it may have been sold again to
    // another customer; the phone is not here either way.
    final alreadyBack = <String>{};
    if (voided && sale.lines.any((l) => l.serialId != null)) {
      for (final l in sale.lines) {
        if (l.serialId == null || l.productId == null) continue;
        final row = (await products.watchSerials(l.productId!).first).where((s) => s.id == l.serialId).firstOrNull;
        if (row == null || row.status != SerialStatus.sold) continue;
        final same = await products.watchSerialRows(row.serial).first;
        if (same.any((s) => s.id != row.id && s.createdAt.isAfter(row.createdAt))) alreadyBack.add(l.id);
      }
    }
    // Un-void mirrors it: a line whose IMEI row was never returned (still sold
    // by this very line) gets no second −1.
    if (!voided) {
      for (final l in sale.lines) {
        if (l.serialId == null || l.productId == null) continue;
        final row = (await products.watchSerials(l.productId!).first).where((s) => s.id == l.serialId).firstOrNull;
        if (row != null && row.status == SerialStatus.sold && row.saleLineId == l.id) alreadyBack.add(l.id);
      }
    }

    await uow.run(UnitKind.voidSale, () async {
      await sales.setVoided(sale.id, voided);
      await stock.addAll(voided
          ? movementsForSale(sale, StockMovementType.voidReturn, sign: 1, where: (l) => !alreadyBack.contains(l.id))
          : movementsForSale(sale, StockMovementType.sale, sign: -1, note: 'unvoid', where: (l) => !alreadyBack.contains(l.id)));
      for (final l in sale.lines) {
        if (l.serialId == null || alreadyBack.contains(l.id)) continue;
        await products.setSerialStatus(
          l.serialId!,
          voided ? SerialStatus.inStock : SerialStatus.sold,
          saleLineId: voided ? null : l.id,
        );
      }
      if (sale.method == PaymentMethod.debt && sale.customerId != null) {
        final t = nowUtc();
        await debt.add(DebtEntry(
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
  }
}

final voidSaleServiceProvider = Provider<VoidSaleService>((ref) => VoidSaleService(
      uow: ref.watch(unitOfWorkProvider),
      sales: ref.watch(salesRepositoryProvider),
      stock: ref.watch(stockRepositoryProvider),
      debt: ref.watch(debtRepositoryProvider),
      products: ref.watch(productRepositoryProvider),
    ));
