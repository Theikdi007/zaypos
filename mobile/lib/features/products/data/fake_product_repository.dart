import '../../../app/fake_database.dart';
import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import 'product_repository.dart';

/// Sample catalog (from the design).
List<Product> seedProducts(String tenantId) {
  final t = nowUtc();
  return [
    for (final p in SeedCatalog.items)
      Product(
        id: p.id,
        tenantId: tenantId,
        name: p.name,
        cost: p.cost,
        price: p.price,
        category: p.category,
        unit: p.unit,
        tint: p.tint,
        initial: p.initial,
        createdAt: t,
        updatedAt: t,
      ),
  ];
}

class FakeProductRepository implements ProductRepository {
  FakeProductRepository(this.db);
  final FakeDatabase db;

  @override
  List<Product> list() => List.unmodifiable(db.products.where((p) => !p.isDeleted));

  @override
  List<ProductVariant> variantsOf(String productId) =>
      List.unmodifiable(db.variants.where((v) => v.productId == productId && v.deletedAt == null));

  @override
  List<ProductBatch> batchesOf(String productId) =>
      List.unmodifiable(db.batches.where((b) => b.productId == productId && b.deletedAt == null));

  @override
  List<ProductSerial> serialsOf(String productId) =>
      List.unmodifiable(db.serials.where((s) => s.productId == productId && s.deletedAt == null));

  @override
  void add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) {
    db.products.insert(0, product);
    db.variants.addAll(variants);
    db.batches.addAll(batches);
    db.serials.addAll(serials);
  }

  @override
  void setSerialStatus(String serialId, SerialStatus status, {String? saleLineId}) {
    final i = db.serials.indexWhere((s) => s.id == serialId);
    if (i < 0) throw StateError('Unknown serial $serialId');
    db.serials[i] = db.serials[i].copyWith(status: status, saleLineId: () => saleLineId, updatedAt: nowUtc());
  }
}
