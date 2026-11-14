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
  Stream<List<Product>> watchAll() =>
      db.watch({FakeTable.products}, () => List.unmodifiable(db.products.where((p) => !p.isDeleted)));

  @override
  Stream<Product?> watchById(String id) =>
      db.watch({FakeTable.products}, () => db.products.where((p) => p.id == id && !p.isDeleted).firstOrNull);

  @override
  Stream<List<ProductVariant>> watchVariants(String productId) => db.watch(
        {FakeTable.variants},
        () => List.unmodifiable(db.variants.where((v) => v.productId == productId && v.deletedAt == null)),
      );

  /// Batch quantity = SUM of its live stock movements, like the Drift repository.
  @override
  Stream<List<ProductBatch>> watchBatches(String productId) => db.watch(
        {FakeTable.batches, FakeTable.stock},
        () => List.unmodifiable([
          for (final b in db.batches.where((b) => b.productId == productId && b.deletedAt == null))
            b.copyWith(
              qtyMilli: db.stock
                  .where((m) => m.batchId == b.id && m.deletedAt == null)
                  .fold<int>(0, (a, m) => a + m.qtyMilli),
            ),
        ]),
      );

  @override
  Stream<List<ProductSerial>> watchSerials(String productId) => db.watch(
        {FakeTable.serials},
        () => List.unmodifiable(db.serials.where((s) => s.productId == productId && s.deletedAt == null)),
      );

  @override
  Future<void> add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) async {
    db.products.insert(0, product);
    db.variants.addAll(variants);
    db.batches.addAll(batches);
    db.serials.addAll(serials);
    db.touch({FakeTable.products, FakeTable.variants, FakeTable.batches, FakeTable.serials});
  }

  @override
  Future<void> setPrice(String productId, int price) async {
    final i = db.products.indexWhere((p) => p.id == productId);
    if (i < 0) throw StateError('Unknown product $productId');
    db.products[i] = db.products[i].copyWith(price: price, updatedAt: nowUtc());
    db.touch({FakeTable.products});
  }

  @override
  Future<void> update(Product product) async {
    final i = db.products.indexWhere((p) => p.id == product.id);
    if (i < 0) throw StateError('Unknown product ${product.id}');
    final current = db.products[i];
    db.products[i] = Product(
      id: current.id,
      tenantId: current.tenantId,
      name: product.name,
      cost: product.cost,
      price: product.price,
      wholesalePrice: product.wholesalePrice,
      lowAlertMilli: product.lowAlertMilli,
      category: product.category,
      unit: product.unit,
      barcode: product.barcode,
      warrantyMonths: product.warrantyMonths,
      expiryAlertDays: product.expiryAlertDays,
      tint: product.tint,
      initial: product.initial,
      createdAt: current.createdAt,
      updatedAt: nowUtc(),
      deletedAt: current.deletedAt,
    );
    db.touch({FakeTable.products});
  }

  @override
  Future<void> setSerialStatus(String serialId, SerialStatus status, {String? saleLineId}) async {
    final i = db.serials.indexWhere((s) => s.id == serialId);
    if (i < 0) throw StateError('Unknown serial $serialId');
    db.serials[i] = db.serials[i].copyWith(status: status, saleLineId: () => saleLineId, updatedAt: nowUtc());
    db.touch({FakeTable.serials});
  }
}
