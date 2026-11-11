import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../domain/stock_movement.dart';
import 'stock_repository.dart';

class FakeStockRepository implements StockRepository {
  FakeStockRepository({required this.tenantId}) {
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
    // Opening counts = the design's current stock figures.
    _items.addAll([
      opening(SeedIds.water, 48),
      opening(SeedIds.oil, 3),
      opening(SeedIds.rice, 20),
      opening(SeedIds.soap, 2),
      opening(SeedIds.eggs, 15),
      opening(SeedIds.noodles, 60),
      // coffee: no movements -> 0 (out of stock)
    ]);
  }

  final String tenantId;
  final _items = <StockMovement>[];

  @override
  List<StockMovement> list() => List.unmodifiable(_items.where((m) => m.deletedAt == null));

  @override
  void addAll(List<StockMovement> movements) => _items.addAll(movements);
}
