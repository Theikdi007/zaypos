import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/sync/sync_limits.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../data/preset_catalog_api.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';

/// Creates a product with its module rows and initial stock as ONE unit of
/// work (product + variants + batches + serials + restock movements).
class ProductService {
  ProductService({required this.uow, required this.products, required this.stock});

  final UnitOfWork uow;
  final ProductRepository products;
  final StockRepository stock;

  Future<void> create(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
    List<StockMovement> initialStock = const [],
  }) {
    for (final m in initialStock) {
      if (m.productId != product.id) throw ArgumentError('Movement for another product');
    }
    return uow.run(UnitKind.upsertProduct, () async {
      await products.add(product, variants: variants, batches: batches, serials: serials);
      await stock.addAll(initialStock);
    });
  }

  /// Sets a product's selling price as ONE upsertProduct unit (POS asks for
  /// it before selling a product without a price). [price] must be positive.
  Future<void> setPrice(String productId, int price) async {
    if (price <= 0) throw ArgumentError.value(price, 'price', 'must be positive');
    await uow.run(UnitKind.upsertProduct, () => products.setPrice(productId, price));
  }

  /// Saves an edited product (Products → tap → edit form) as ONE
  /// upsertProduct unit. [product.price] must be positive.
  ///
  /// New module rows added in the edit form go in the same unit (BUG-12):
  /// new sizes/colours and batches start empty; each new IMEI is a phone in
  /// hand, so [serials] come with a matching restock of their count.
  /// Existing module rows are never changed or deleted.
  Future<void> update(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
    List<StockMovement> movements = const [],
  }) async {
    if (product.price <= 0) throw ArgumentError.value(product.price, 'price', 'must be positive');
    for (final m in movements) {
      if (m.productId != product.id) throw ArgumentError('Movement for another product');
    }
    for (final r in [...variants.map((v) => v.productId), ...batches.map((b) => b.productId), ...serials.map((s) => s.productId)]) {
      if (r != product.id) throw ArgumentError('Module row for another product');
    }
    await uow.run(UnitKind.upsertProduct, () async {
      await products.update(product);
      if (variants.isNotEmpty || batches.isNotEmpty || serials.isNotEmpty) {
        await products.addModules(variants: variants, batches: batches, serials: serials);
      }
      if (movements.isNotEmpty) await stock.addAll(movements);
      if (serials.isNotEmpty) {
        await stock.addAll([
          restockMovement(
            tenantId: product.tenantId,
            productId: product.id,
            qtyMilli: Qty.units(serials.length),
            note: 'IMEI added',
          ),
        ]);
      }
    });
  }

  /// Many products (e.g. the preset catalog) as ONE upsertProduct unit.
  Future<void> importAll(List<Product> items) => uow.run(UnitKind.upsertProduct, () async {
        for (final p in items) {
          await products.add(p);
        }
      });
}

/// Register step 3 "ကြိုတင်စာရင်း" (§7): the template's starter items become
/// products in ONE upsertProduct unit, without prices (the owner fills them).
/// Barcodes are normalized like the server; a missing category gets a default.
List<Product> productsFromPresets(
  List<PresetItem> items, {
  required String tenantId,
  required int tint,
  required SyncLimitsData limits,
  DateTime? at,
}) {
  final t = at ?? nowUtc();
  return [
    for (final i in items)
      if (i.name.trim().isNotEmpty)
        Product(
          id: newId(),
          tenantId: tenantId,
          name: i.name.trim(),
          cost: 0,
          price: 0,
          category: i.category.trim().isEmpty ? 'အထွေထွေ' : i.category.trim(),
          unit: i.unit.trim(),
          barcode: switch (limits.normalize('products.barcode', i.barcode ?? '')) {
            '' => null,
            final b => limits.checkText('products.barcode', b, label: 'Barcode') == null ? b : null,
          },
          tint: tint,
          initial: String.fromCharCode(i.name.trim().runes.first),
          createdAt: t,
          updatedAt: t,
        ),
  ];
}

final productServiceProvider = Provider<ProductService>((ref) => ProductService(
      uow: ref.watch(unitOfWorkProvider),
      products: ref.watch(productRepositoryProvider),
      stock: ref.watch(stockRepositoryProvider),
    ));
