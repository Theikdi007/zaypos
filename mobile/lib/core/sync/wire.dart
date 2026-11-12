// Drift row -> /sync/push JSON (backend SyncRows.cs). Property names are the
// column names; times are ISO-8601 UTC with milliseconds; enums are their
// camelCase names; calendar dates are "yyyy-MM-dd".

import '../db/app_database.dart';

String isoMs(DateTime t) => t.toUtc().toIso8601String();

String? _iso(DateTime? t) => t == null ? null : isoMs(t);

String? _date(DateTime? d) {
  if (d == null) return null;
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

Map<String, Object?> _base(String id, String tenantId, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt) => {
      'id': id,
      'tenantId': tenantId,
      'createdAt': isoMs(createdAt),
      'updatedAt': isoMs(updatedAt),
      'deletedAt': _iso(deletedAt),
    };

/// Server table names, in the order they are listed in `UnitRows`.
abstract final class WireTable {
  static const tenants = 'tenants';
  static const tenantFeatures = 'tenantFeatures';
  static const devices = 'devices';
  static const products = 'products';
  static const productVariants = 'productVariants';
  static const productBatches = 'productBatches';
  static const productSerials = 'productSerials';
  static const customers = 'customers';
  static const sales = 'sales';
  static const saleLines = 'saleLines';
  static const payments = 'payments';
  static const stockMovements = 'stockMovements';
  static const debtEntries = 'debtEntries';
}

Map<String, Object?> tenantFeatureWire(TenantFeatureRow r) => {
      'tenantId': r.tenantId,
      'featureKey': r.featureKey,
      'enabled': r.enabled,
      'updatedAt': isoMs(r.updatedAt),
    };

/// The server only takes lastSeq from a device row (it never moves back).
Map<String, Object?> deviceWire(DeviceRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'code': r.code,
      'name': r.name,
      'lastSeq': r.lastSeq,
    };

Map<String, Object?> productWire(ProductRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'name': r.name,
      'category': r.category,
      'unit': r.unit,
      'barcode': r.barcode,
      'cost': r.cost,
      'price': r.price,
      'wholesalePrice': r.wholesalePrice,
      'lowAlertMilli': r.lowAlertMilli,
      'warrantyMonths': r.warrantyMonths,
      'expiryAlertDays': r.expiryAlertDays,
      // ARGB 0xFFxxxxxx locally; the server column is a signed 32-bit int
      // (the same bits). See WireDecoder.product for the way back.
      'tint': r.tint.toSigned(32),
      'initial': r.initial,
    };

Map<String, Object?> variantWire(ProductVariantRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'productId': r.productId,
      'size': r.size,
      'color': r.color,
    };

Map<String, Object?> batchWire(ProductBatchRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'productId': r.productId,
      'batchNo': r.batchNo,
      'expiryDate': _date(r.expiryDate),
    };

Map<String, Object?> serialWire(ProductSerialRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'productId': r.productId,
      'serial': r.serial,
      'status': r.status.name,
      'saleLineId': r.saleLineId,
    };

Map<String, Object?> customerWire(CustomerRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'name': r.name,
      'phone': r.phone,
      'address': r.address,
      'creditLimit': r.creditLimit,
      'note': r.note,
    };

/// syncedAt is server output only and never sent.
Map<String, Object?> saleWire(SaleRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'no': r.no,
      'deviceId': r.deviceId,
      'method': r.method.name,
      'customerId': r.customerId,
      'customerName': r.customerName,
      'total': r.total,
      'voidedAt': _iso(r.voidedAt),
    };

Map<String, Object?> saleLineWire(SaleLineRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'saleId': r.saleId,
      'productId': r.productId,
      'variantId': r.variantId,
      'batchId': r.batchId,
      'serialId': r.serialId,
      'name': r.name,
      'qtyMilli': r.qtyMilli,
      'price': r.price,
      'costSnapshot': r.costSnapshot,
      'lineTotal': r.lineTotal,
    };

Map<String, Object?> paymentWire(PaymentRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'saleId': r.saleId,
      'method': r.method.name,
      'amount': r.amount,
      'received': r.received,
    };

Map<String, Object?> movementWire(StockMovementRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'productId': r.productId,
      'variantId': r.variantId,
      'batchId': r.batchId,
      'type': r.type.name,
      'qtyMilli': r.qtyMilli,
      'saleId': r.saleId,
      'note': r.note,
      'deviceId': r.deviceId,
    };

Map<String, Object?> debtWire(DebtEntryRow r) => {
      ..._base(r.id, r.tenantId, r.createdAt, r.updatedAt, r.deletedAt),
      'customerId': r.customerId,
      'type': r.type.name,
      'amount': r.amount,
      'saleId': r.saleId,
      'saleNo': r.saleNo,
      'method': r.method?.name,
      'note': r.note,
      'deviceId': r.deviceId,
    };
