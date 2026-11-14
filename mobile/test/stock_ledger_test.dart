import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/data/stock_providers.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/products/domain/product_view.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';

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

    test('tracked only after a live restock/adjustment > 0', () {
      final levels = stockLevels([
        _m('sold', StockMovementType.sale, -2000),
        _m('voided', StockMovementType.sale, -1000),
        _m('voided', StockMovementType.voidReturn, 1000),
        _m('down', StockMovementType.adjustment, -1000),
        _m('deleted', StockMovementType.restock, 5000, deletedAt: DateTime.utc(2026)),
        _m('restocked', StockMovementType.restock, 1000),
        _m('counted', StockMovementType.adjustment, 3000),
        _m('counted', StockMovementType.sale, -3000),
      ]);
      expect(levels, {
        'sold': const StockLevel(-2000, tracked: false),
        'voided': const StockLevel(0, tracked: false),
        'down': const StockLevel(-1000, tracked: false),
        'restocked': const StockLevel(1000, tracked: true),
        'counted': const StockLevel(0, tracked: true),
      });
    });
  });

  group('ProductView (cached stock in the read model only)', () {
    test('seeded stock equals the design figures', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final views = await val(c, productsProvider);
      ProductView v(String id) => views.firstWhere((p) => p.id == id);
      expect(v(SeedIds.water).stockMilli, Qty.units(48));
      expect(v(SeedIds.oil).isLow, isTrue);
      expect(v(SeedIds.coffee).isOut, isTrue);
    });

    test('checkout and void update the computed stock', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final sale = await sell(c, [draft(productId: SeedIds.water, name: 'ရေသန့် 1L', qtyMilli: Qty.units(2), price: 600, cost: 450)]);
      Future<int> water() async => (await val(c, productsProvider)).firstWhere((p) => p.id == SeedIds.water).stockMilli;
      expect(await water(), Qty.units(46));
      await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
      expect(await water(), Qty.units(48));
      expect(stockOf((await val(c, stockMovementsProvider)).where((m) => m.productId == SeedIds.water)), Qty.units(48));
    });
  });
}
