import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/sync/sync_limits.dart';
import '../../../core/utils/ids.dart';
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
