import 'package:drift/drift.dart';

import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../../../core/utils/ids.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import 'product_repository.dart';

class DriftProductRepository implements ProductRepository {
  DriftProductRepository(this.db);
  final AppDatabase db;

  @override
  Stream<List<Product>> watchAll() => (db.select(db.products)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt), (p) => OrderingTerm.asc(p.name)]))
      .map(productFromRow)
      .watch();

  @override
  Stream<Product?> watchById(String id) =>
      (db.select(db.products)..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
          .map(productFromRow)
          .watchSingleOrNull();

  @override
  Stream<List<ProductVariant>> watchVariants(String productId) => (db.select(db.productVariants)
        ..where((v) => v.productId.equals(productId) & v.deletedAt.isNull())
        ..orderBy([(v) => OrderingTerm.asc(v.createdAt)]))
      .map(variantFromRow)
      .watch();

  /// Batch quantity = SUM of its live stock movements (§3.3).
  @override
  Stream<List<ProductBatch>> watchBatches(String productId) {
    final b = db.productBatches;
    final m = db.stockMovements;
    final stock = coalesce([m.qtyMilli.sum(), const Constant(0)]);
    final q = db.select(b).join([
      leftOuterJoin(m, m.batchId.equalsExp(b.id) & m.deletedAt.isNull(), useColumns: false),
    ])
      ..addColumns([stock])
      ..where(b.productId.equals(productId) & b.deletedAt.isNull())
      ..groupBy([b.id])
      ..orderBy([OrderingTerm.asc(b.createdAt)]);
    return q.map((r) => batchFromRow(r.readTable(b), r.read(stock)!)).watch();
  }

  @override
  Stream<List<ProductSerial>> watchSerials(String productId) => (db.select(db.productSerials)
        ..where((s) => s.productId.equals(productId) & s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
      .map(serialFromRow)
      .watch();

  @override
  Stream<Set<String>> watchInStockSerialValues() {
    final s = db.productSerials;
    return (db.selectOnly(s)
          ..addColumns([s.serial])
          ..where(s.deletedAt.isNull() & s.status.equalsValue(SerialStatus.inStock)))
        .map((r) => r.read(s.serial)!)
        .watch()
        .map((l) => l.toSet());
  }

  @override
  Future<void> add(
    Product product, {
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) async {
    final rec = UnitRecorder.require();
    final p = productRow(product);
    await db.into(db.products).insert(p);
    rec.record(WireTable.products, productWire(p));
    await addModules(variants: variants, batches: batches, serials: serials);
  }

  @override
  Future<void> addModules({
    List<ProductVariant> variants = const [],
    List<ProductBatch> batches = const [],
    List<ProductSerial> serials = const [],
  }) async {
    final rec = UnitRecorder.require();
    for (final v in variants.map(variantRow)) {
      await db.into(db.productVariants).insert(v);
      rec.record(WireTable.productVariants, variantWire(v));
    }
    for (final b in batches.map(batchRow)) {
      await db.into(db.productBatches).insert(b);
      rec.record(WireTable.productBatches, batchWire(b));
    }
    for (final s in serials.map(serialRow)) {
      await db.into(db.productSerials).insert(s);
      rec.record(WireTable.productSerials, serialWire(s));
    }
  }

  /// Records the full product row (the server's products rule is LWW on the row).
  @override
  Future<void> setPrice(String productId, int price) async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (current == null) throw StateError('Unknown product $productId');
    final updated = current.copyWith(price: price, updatedAt: nowUtc());
    await db.update(db.products).replace(updated);
    rec.record(WireTable.products, productWire(updated));
  }

  @override
  Future<void> update(Product product) async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.products)..where((p) => p.id.equals(product.id))).getSingleOrNull();
    if (current == null) throw StateError('Unknown product ${product.id}');
    final row = productRow(product.copyWith(updatedAt: nowUtc()));
    // Keep identity/history columns as stored.
    final updated = row.copyWith(tenantId: current.tenantId, createdAt: current.createdAt, deletedAt: Value(current.deletedAt));
    await db.update(db.products).replace(updated);
    rec.record(WireTable.products, productWire(updated));
  }

  @override
  Future<void> setSerialStatus(String serialId, SerialStatus status, {String? saleLineId}) async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.productSerials)..where((s) => s.id.equals(serialId))).getSingleOrNull();
    if (current == null) throw StateError('Unknown serial $serialId');
    final updated = current.copyWith(status: status, saleLineId: Value(saleLineId), updatedAt: nowUtc());
    await db.update(db.productSerials).replace(updated);
    rec.record(WireTable.productSerials, serialWire(updated));
  }
}
