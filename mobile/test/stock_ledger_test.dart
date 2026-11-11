import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/data/stock_providers.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product_view.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

StockMovement _m(String product, StockMovementType type, int qty, {DateTime? deletedAt, String? variantId}) {
  final t = DateTime.utc(2026);
  return StockMovement(
    id: '$product$type$qty',
    tenantId: 't',
    productId: product,
    variantId: variantId,
    type: type,
    qtyMilli: qty,
    createdAt: t,
    updatedAt: t,
    deletedAt: deletedAt,
  );
}

void main() {
  group('stockOf / stockByProduct', () {
    test('stock is the sum of signed movements', () {
      final ms = [
        _m('p', StockMovementType.adjustment, 10000),
        _m('p', StockMovementType.sale, -2500),
        _m('p', StockMovementType.restock, 6000),
        _m('p', StockMovementType.voidReturn, 1000),
      ];
      expect(stockOf(ms), 10000 - 2500 + 6000 + 1000);
    });

    test('soft-deleted movements are ignored', () {
      expect(stockOf([_m('p', StockMovementType.restock, 5000), _m('p', StockMovementType.sale, -1000, deletedAt: DateTime.utc(2026))]), 5000);
    });

    test('grouped per product; variants roll up to their product', () {
      final by = stockByProduct([
        _m('a', StockMovementType.restock, 3000, variantId: 'a-M'),
        _m('a', StockMovementType.restock, 2000, variantId: 'a-L'),
        _m('b', StockMovementType.restock, 1000),
      ]);
      expect(by, {'a': 5000, 'b': 1000});
    });
  });

  group('ProductView (cached stock in the read model only)', () {
    test('seeded stock equals the design figures', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      ProductView v(String id) => c.read(productsProvider).firstWhere((p) => p.id == id);
      expect(v(SeedIds.water).stockMilli, Qty.units(48));
      expect(v(SeedIds.oil).isLow, isTrue);
      expect(v(SeedIds.coffee).isOut, isTrue);
    });

    test('recording movements updates the computed stock', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final stock = c.read(stockLedgerProvider.notifier);
      final sale = c.read(salesProvider.notifier).create(
        method: PaymentMethod.cash,
        lines: [draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450)],
      );
      stock.record(stock.forSale(sale, StockMovementType.sale, sign: -1));
      int water() => c.read(productsProvider).firstWhere((p) => p.id == SeedIds.water).stockMilli;
      expect(water(), Qty.units(46));
      stock.record(stock.forSale(sale, StockMovementType.voidReturn, sign: 1));
      expect(water(), Qty.units(48));
      expect(stockOf(c.read(stockLedgerProvider).where((m) => m.productId == SeedIds.water)), Qty.units(48));
    });
  });
}
