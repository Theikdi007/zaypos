import '../../../app/fake_database.dart';
import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../domain/stock_movement.dart';
import 'stock_repository.dart';

/// Opening counts = the design's current stock figures.
List<StockMovement> seedStock(String tenantId) {
  final at = daysAgoAt(30, 8, 0);
  StockMovement opening(String productId, int units) => StockMovement(
    id: newId(),
    tenantId: tenantId,
    productId: productId,
    type: StockMovementType.adjustment,
    qtyMilli: Qty.units(units),
    note: 'opening count',
    createdAt: at,
    updatedAt: at,
  );
  return [
    opening(SeedIds.water, 48),
    opening(SeedIds.oil, 3),
    opening(SeedIds.rice, 20),
    opening(SeedIds.soap, 2),
    opening(SeedIds.eggs, 15),
    opening(SeedIds.noodles, 60),
    // coffee: no movements -> 0 (out of stock)
  ];
}

class FakeStockRepository implements StockRepository {
  FakeStockRepository(this.db);
  final FakeDatabase db;

  @override
  Stream<List<StockMovement>> watchAll() =>
      db.watch({FakeTable.stock}, () => List.unmodifiable(db.stock.where((m) => m.deletedAt == null)));

  @override
  Stream<Map<String, int>> watchStockByProduct() => db.watch({FakeTable.stock}, () => stockByProduct(db.stock));

  @override
  Future<void> addAll(List<StockMovement> movements) async {
    if (movements.isEmpty) return;
    db.stock.addAll(movements);
    db.touch({FakeTable.stock});
  }
}
