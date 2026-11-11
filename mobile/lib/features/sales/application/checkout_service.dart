import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/data/debt_repository.dart';
import '../../customers/domain/debt_entry.dart';
import '../../devices/data/device_repository.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product_modules.dart';
import '../data/sales_providers.dart' show SaleLineDraft;
import '../data/sales_repository.dart';
import '../domain/sale.dart';

enum CheckoutError {
  /// Nothing to sell.
  emptyCart,

  /// Credit sale without a (known) customer.
  customerRequired,

  /// Cash received is less than the total.
  insufficientCash,
}

class CheckoutException implements Exception {
  const CheckoutException(this.error);
  final CheckoutError error;

  @override
  String toString() => 'CheckoutException($error)';
}

class CheckoutRequest {
  const CheckoutRequest({required this.lines, required this.method, this.customerId, this.received});

  final List<SaleLineDraft> lines;
  final PaymentMethod method;

  /// Required when [method] is debt.
  final String? customerId;

  /// Cash handed over (kyats); null = exact amount.
  final int? received;
}

/// Records a sale as ONE unit of work: receipt number, sale + lines +
/// payment, stock movements, serial status and (for credit) the debt entry.
/// Either all of it is stored or none of it.
class CheckoutService {
  CheckoutService({
    required this.uow,
    required this.tenantId,
    required this.sales,
    required this.stock,
    required this.debt,
    required this.customers,
    required this.devices,
    required this.products,
  });

  final UnitOfWork uow;
  final String tenantId;
  final SalesRepository sales;
  final StockRepository stock;
  final DebtRepository debt;
  final CustomerRepository customers;
  final DeviceRepository devices;
  final ProductRepository products;

  Future<Sale> checkout(CheckoutRequest r) async {
    if (r.lines.isEmpty) throw const CheckoutException(CheckoutError.emptyCart);
    final isDebt = r.method == PaymentMethod.debt;
    String? customerName;
    if (isDebt) {
      final id = r.customerId;
      final match = id == null ? null : await customers.watchById(id).first;
      if (match == null) throw const CheckoutException(CheckoutError.customerRequired);
      customerName = match.name;
    }

    return uow.run(() async {
      final id = newId();
      final t = nowUtc();
      final lines = [
        for (final l in r.lines)
          SaleLine(
            id: newId(),
            tenantId: tenantId,
            saleId: id,
            productId: l.productId,
            variantId: l.variantId,
            batchId: l.batchId,
            serialId: l.serialId,
            name: l.name,
            qtyMilli: l.qtyMilli,
            price: l.price,
            costSnapshot: l.cost,
            createdAt: t,
            updatedAt: t,
          ),
      ];
      final total = lines.fold(0, (a, l) => a + l.total);
      if (r.method == PaymentMethod.cash && r.received != null && r.received! < total) {
        throw const CheckoutException(CheckoutError.insufficientCash);
      }
      final sale = Sale(
        id: id,
        tenantId: tenantId,
        no: await devices.issueReceiptNo(),
        method: r.method,
        lines: lines,
        payments: isDebt
            ? const []
            : [
                Payment(
                  id: newId(),
                  tenantId: tenantId,
                  saleId: id,
                  method: r.method,
                  amount: total,
                  received: r.method == PaymentMethod.cash ? r.received : null,
                  createdAt: t,
                  updatedAt: t,
                ),
              ],
        customerId: isDebt ? r.customerId : null,
        customerName: customerName,
        createdAt: t,
        updatedAt: t,
      );
      await sales.add(sale);
      await stock.addAll(movementsForSale(sale, StockMovementType.sale, sign: -1));
      for (final l in lines) {
        if (l.serialId != null) await products.setSerialStatus(l.serialId!, SerialStatus.sold, saleLineId: l.id);
      }
      if (isDebt) {
        await debt.add(DebtEntry(
          id: newId(),
          tenantId: tenantId,
          customerId: r.customerId!,
          type: DebtEntryType.creditSale,
          amount: total,
          saleId: sale.id,
          saleNo: sale.no,
          createdAt: t,
          updatedAt: t,
        ));
      }
      return sale;
    });
  }
}

final checkoutServiceProvider = Provider<CheckoutService>((ref) => CheckoutService(
      uow: ref.read(unitOfWorkProvider),
      tenantId: ref.read(tenantIdProvider),
      sales: ref.read(salesRepositoryProvider),
      stock: ref.read(stockRepositoryProvider),
      debt: ref.read(debtRepositoryProvider),
      customers: ref.read(customerRepositoryProvider),
      devices: ref.read(deviceRepositoryProvider),
      products: ref.read(productRepositoryProvider),
    ));
