import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import 'product_repository.dart';

/// In-memory sample data (from the design). Replaced by API + Drift later.
class FakeProductRepository implements ProductRepository {
  FakeProductRepository({required this.tenantId}) {
    final t = nowUtc();
    _items.addAll([
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
    ]);
  }

  final String tenantId;
  final _items = <Product>[];
  final _variants = <ProductVariant>[];
  final _batches = <ProductBatch>[];
  final _serials = <ProductSerial>[];

  @override
  List<Product> list() => List.unmodifiable(_items.where((p) => !p.isDeleted));

  @override
  List<ProductVariant> variantsOf(String productId) =>
      List.unmodifiable(_variants.where((v) => v.productId == productId && v.deletedAt == null));

  @override
  List<ProductBatch> batchesOf(String productId) =>
      List.unmodifiable(_batches.where((b) => b.productId == productId && b.deletedAt == null));

  @override
  List<ProductSerial> serialsOf(String productId) =>
      List.unmodifiable(_serials.where((s) => s.productId == productId && s.deletedAt == null));

  @override
  void add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) {
    _items.insert(0, product);
    _variants.addAll(variants);
    _batches.addAll(batches);
    _serials.addAll(serials);
  }
}
