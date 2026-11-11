import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../../devices/data/device_providers.dart';
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

class SalesNotifier extends Notifier<List<Sale>> {
  SalesRepository get _repo => ref.read(salesRepositoryProvider);

  @override
  List<Sale> build() => _repo.list();

  /// Records a sale. Non-credit sales get a [Payment]; credit sales are
  /// recorded in the debt ledger by the caller.
  Sale create({
    required PaymentMethod method,
    required List<SaleLineDraft> lines,
    String? customerId,
    String? customerName,
    int? received,
  }) {
    final tenantId = ref.read(tenantIdProvider);
    final id = newId();
    final t = nowUtc();
    final saleLines = [
      for (final l in lines)
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
    final total = saleLines.fold(0, (a, l) => a + l.total);
    final sale = Sale(
      id: id,
      tenantId: tenantId,
      no: ref.read(deviceProvider.notifier).issueReceiptNo(),
      method: method,
      lines: saleLines,
      payments: method == PaymentMethod.debt
          ? const []
          : [
              Payment(
                id: newId(),
                tenantId: tenantId,
                saleId: id,
                method: method,
                amount: total,
                received: received,
                createdAt: t,
                updatedAt: t,
              ),
            ],
      customerId: customerId,
      customerName: customerName,
      createdAt: t,
      updatedAt: t,
    );
    _repo.add(sale);
    state = _repo.list();
    return sale;
  }

  void setVoided(String id, bool voided) {
    _repo.setVoided(id, voided);
    state = _repo.list();
  }
}

final salesProvider = NotifierProvider<SalesNotifier, List<Sale>>(SalesNotifier.new);

final saleByIdProvider = Provider.family<Sale?, String>((ref, id) {
  for (final s in ref.watch(salesProvider)) {
    if (s.id == id) return s;
  }
  return null;
});
