// /sync/pull JSON (backend SyncRows.cs, server output) -> Drift rows.
// Inverse of wire.dart. Throws FormatException on a row that cannot be
// stored, so the whole page is rolled back and the cursor stays put.

import '../../features/customers/domain/debt_entry.dart';
import '../../features/inventory/domain/stock_movement.dart';
import '../../features/products/domain/product_modules.dart';
import '../../features/sales/domain/sale.dart';
import '../db/app_database.dart';

typedef Json = Map<String, dynamic>;

/// Decodes rows of one tenant; [tenantId] fills rows that omit it.
class WireDecoder {
  const WireDecoder(this.tenantId);
  final String tenantId;

  static T _req<T>(Json j, String key, String table) {
    final v = j[key];
    if (v is T) return v;
    throw FormatException('$table.$key: expected $T, got ${v.runtimeType}');
  }

  static String _s(Json j, String k, String t) => _req<String>(j, k, t);
  static String? _so(Json j, String k) => j[k] as String?;
  static int _i(Json j, String k, String t) => (_req<num>(j, k, t)).toInt();
  static int? _io(Json j, String k) => (j[k] as num?)?.toInt();

  /// ISO-8601 → UTC, whole milliseconds (same precision as the server).
  static DateTime _time(String s) {
    final t = DateTime.parse(s).toUtc();
    return DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
  }

  static DateTime _t(Json j, String k, String t) => _time(_s(j, k, t));
  static DateTime? _to(Json j, String k) => j[k] == null ? null : _time(j[k] as String);

  /// "yyyy-MM-dd" → UTC midnight.
  static DateTime? _date(Json j, String k) {
    final s = j[k] as String?;
    if (s == null) return null;
    final d = DateTime.parse(s);
    return DateTime.utc(d.year, d.month, d.day);
  }

  static E _enum<E extends Enum>(List<E> values, Json j, String k, String t) {
    final name = _s(j, k, t);
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw FormatException('$t.$k: unknown value "$name"');
  }

  static E? _enumO<E extends Enum>(List<E> values, Json j, String k, String t) =>
      j[k] == null ? null : _enum(values, j, k, t);

  String _tenant(Json j) => _so(j, 'tenantId') ?? tenantId;

  TenantRow tenant(Json j) => TenantRow(
        id: _s(j, 'id', 'tenants'),
        tenantId: _tenant(j),
        name: _s(j, 'name', 'tenants'),
        templateId: _so(j, 'templateId') ?? 'grocery',
        township: _so(j, 'township'),
        plan: _so(j, 'plan'),
        planExpiresAt: _to(j, 'planExpiresAt'),
        createdAt: _t(j, 'createdAt', 'tenants'),
        updatedAt: _t(j, 'updatedAt', 'tenants'),
        deletedAt: _to(j, 'deletedAt'),
      );

  TenantFeatureRow feature(Json j) => TenantFeatureRow(
        tenantId: _tenant(j),
        featureKey: _s(j, 'featureKey', 'tenantFeatures'),
        enabled: _req<bool>(j, 'enabled', 'tenantFeatures'),
        updatedAt: _t(j, 'updatedAt', 'tenantFeatures'),
      );

  DeviceRow device(Json j) => DeviceRow(
        id: _s(j, 'id', 'devices'),
        tenantId: _tenant(j),
        code: _s(j, 'code', 'devices'),
        name: _so(j, 'name'),
        lastSeq: _io(j, 'lastSeq') ?? 0,
        lastSyncAt: _to(j, 'lastSyncAt'),
        createdAt: _t(j, 'createdAt', 'devices'),
        updatedAt: _t(j, 'updatedAt', 'devices'),
        deletedAt: _to(j, 'deletedAt'),
      );

  ProductRow product(Json j) => ProductRow(
        id: _s(j, 'id', 'products'),
        tenantId: _tenant(j),
        name: _s(j, 'name', 'products'),
        category: _s(j, 'category', 'products'),
        unit: _so(j, 'unit') ?? '',
        barcode: _so(j, 'barcode'),
        cost: _i(j, 'cost', 'products'),
        price: _i(j, 'price', 'products'),
        wholesalePrice: _io(j, 'wholesalePrice'),
        lowAlertMilli: _i(j, 'lowAlertMilli', 'products'),
        warrantyMonths: _io(j, 'warrantyMonths'),
        expiryAlertDays: _io(j, 'expiryAlertDays'),
        // Server int32 (e.g. -2039584) → the ARGB colour (0xFFE0E0E0).
        tint: _i(j, 'tint', 'products').toUnsigned(32),
        initial: _s(j, 'initial', 'products'),
        createdAt: _t(j, 'createdAt', 'products'),
        updatedAt: _t(j, 'updatedAt', 'products'),
        deletedAt: _to(j, 'deletedAt'),
      );

  ProductVariantRow variant(Json j) => ProductVariantRow(
        id: _s(j, 'id', 'productVariants'),
        tenantId: _tenant(j),
        productId: _s(j, 'productId', 'productVariants'),
        size: _s(j, 'size', 'productVariants'),
        color: _s(j, 'color', 'productVariants'),
        createdAt: _t(j, 'createdAt', 'productVariants'),
        updatedAt: _t(j, 'updatedAt', 'productVariants'),
        deletedAt: _to(j, 'deletedAt'),
      );

  ProductBatchRow batch(Json j) => ProductBatchRow(
        id: _s(j, 'id', 'productBatches'),
        tenantId: _tenant(j),
        productId: _s(j, 'productId', 'productBatches'),
        batchNo: _s(j, 'batchNo', 'productBatches'),
        expiryDate: _date(j, 'expiryDate'),
        createdAt: _t(j, 'createdAt', 'productBatches'),
        updatedAt: _t(j, 'updatedAt', 'productBatches'),
        deletedAt: _to(j, 'deletedAt'),
      );

  ProductSerialRow serial(Json j) => ProductSerialRow(
        id: _s(j, 'id', 'productSerials'),
        tenantId: _tenant(j),
        productId: _s(j, 'productId', 'productSerials'),
        serial: _s(j, 'serial', 'productSerials'),
        status: _enum(SerialStatus.values, j, 'status', 'productSerials'),
        saleLineId: _so(j, 'saleLineId'),
        createdAt: _t(j, 'createdAt', 'productSerials'),
        updatedAt: _t(j, 'updatedAt', 'productSerials'),
        deletedAt: _to(j, 'deletedAt'),
      );

  CustomerRow customer(Json j) => CustomerRow(
        id: _s(j, 'id', 'customers'),
        tenantId: _tenant(j),
        name: _s(j, 'name', 'customers'),
        phone: _so(j, 'phone') ?? '',
        address: _so(j, 'address'),
        creditLimit: _io(j, 'creditLimit'),
        note: _so(j, 'note'),
        createdAt: _t(j, 'createdAt', 'customers'),
        updatedAt: _t(j, 'updatedAt', 'customers'),
        deletedAt: _to(j, 'deletedAt'),
      );

  SaleRow sale(Json j) => SaleRow(
        id: _s(j, 'id', 'sales'),
        tenantId: _tenant(j),
        no: _s(j, 'no', 'sales'),
        deviceId: _so(j, 'deviceId'),
        method: _enum(PaymentMethod.values, j, 'method', 'sales'),
        customerId: _so(j, 'customerId'),
        customerName: _so(j, 'customerName'),
        total: _i(j, 'total', 'sales'),
        voidedAt: _to(j, 'voidedAt'),
        syncedAt: _to(j, 'syncedAt'),
        createdAt: _t(j, 'createdAt', 'sales'),
        updatedAt: _t(j, 'updatedAt', 'sales'),
        deletedAt: _to(j, 'deletedAt'),
      );

  SaleLineRow saleLine(Json j) => SaleLineRow(
        id: _s(j, 'id', 'saleLines'),
        tenantId: _tenant(j),
        saleId: _s(j, 'saleId', 'saleLines'),
        productId: _so(j, 'productId'),
        variantId: _so(j, 'variantId'),
        batchId: _so(j, 'batchId'),
        serialId: _so(j, 'serialId'),
        name: _s(j, 'name', 'saleLines'),
        qtyMilli: _i(j, 'qtyMilli', 'saleLines'),
        price: _i(j, 'price', 'saleLines'),
        costSnapshot: _i(j, 'costSnapshot', 'saleLines'),
        lineTotal: _i(j, 'lineTotal', 'saleLines'),
        createdAt: _t(j, 'createdAt', 'saleLines'),
        updatedAt: _t(j, 'updatedAt', 'saleLines'),
        deletedAt: _to(j, 'deletedAt'),
      );

  PaymentRow payment(Json j) => PaymentRow(
        id: _s(j, 'id', 'payments'),
        tenantId: _tenant(j),
        saleId: _s(j, 'saleId', 'payments'),
        method: _enum(PaymentMethod.values, j, 'method', 'payments'),
        amount: _i(j, 'amount', 'payments'),
        received: _io(j, 'received'),
        createdAt: _t(j, 'createdAt', 'payments'),
        updatedAt: _t(j, 'updatedAt', 'payments'),
        deletedAt: _to(j, 'deletedAt'),
      );

  StockMovementRow movement(Json j) => StockMovementRow(
        id: _s(j, 'id', 'stockMovements'),
        tenantId: _tenant(j),
        productId: _s(j, 'productId', 'stockMovements'),
        variantId: _so(j, 'variantId'),
        batchId: _so(j, 'batchId'),
        type: _enum(StockMovementType.values, j, 'type', 'stockMovements'),
        qtyMilli: _i(j, 'qtyMilli', 'stockMovements'),
        saleId: _so(j, 'saleId'),
        note: _so(j, 'note') ?? '',
        deviceId: _so(j, 'deviceId'),
        createdAt: _t(j, 'createdAt', 'stockMovements'),
        updatedAt: _t(j, 'updatedAt', 'stockMovements'),
        deletedAt: _to(j, 'deletedAt'),
      );

  DebtEntryRow debt(Json j) => DebtEntryRow(
        id: _s(j, 'id', 'debtEntries'),
        tenantId: _tenant(j),
        customerId: _s(j, 'customerId', 'debtEntries'),
        type: _enum(DebtEntryType.values, j, 'type', 'debtEntries'),
        amount: _i(j, 'amount', 'debtEntries'),
        saleId: _so(j, 'saleId'),
        saleNo: _so(j, 'saleNo'),
        method: _enumO(PaymentMethod.values, j, 'method', 'debtEntries'),
        note: _so(j, 'note'),
        deviceId: _so(j, 'deviceId'),
        createdAt: _t(j, 'createdAt', 'debtEntries'),
        updatedAt: _t(j, 'updatedAt', 'debtEntries'),
        deletedAt: _to(j, 'deletedAt'),
      );

  SyncIssueRow issue(Json j) => SyncIssueRow(
        id: _s(j, 'id', 'syncIssues'),
        tenantId: _tenant(j),
        kind: _s(j, 'kind', 'syncIssues'),
        entityTable: _so(j, 'entityTable') ?? '',
        entityId: _so(j, 'entityId') ?? '',
        detail: _so(j, 'detail') ?? '',
        deviceId: _so(j, 'deviceId'),
        resolvedAt: _to(j, 'resolvedAt'),
        createdAt: _t(j, 'createdAt', 'syncIssues'),
        updatedAt: _t(j, 'updatedAt', 'syncIssues'),
        deletedAt: _to(j, 'deletedAt'),
      );
}
