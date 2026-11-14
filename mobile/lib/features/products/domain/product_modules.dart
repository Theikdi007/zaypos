// Module entities enabled by TenantFeatures (expiryBatch, serialWarranty).

/// A received lot with an expiry date (pharmacy / food). Stock per batch is
/// the sum of StockMovements with this batchId; [qtyMilli] is the quantity
/// originally received.
class ProductBatch {
  const ProductBatch({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.batchNo,
    required this.qtyMilli,
    required this.createdAt,
    required this.updatedAt,
    this.expiryDate,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String batchNo;

  /// Calendar date (UTC midnight); null if not tracked for this lot.
  final DateTime? expiryDate;
  final int qtyMilli;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Past its expiry date on [now]'s local calendar day (sold on the expiry
  /// day itself is still allowed). Undated batches never expire.
  bool isExpired(DateTime now) {
    final e = expiryDate;
    if (e == null) return false;
    final local = now.toLocal();
    return DateTime.utc(e.year, e.month, e.day).isBefore(DateTime.utc(local.year, local.month, local.day));
  }

  ProductBatch copyWith({int? qtyMilli, DateTime? updatedAt, DateTime? Function()? deletedAt}) => ProductBatch(
        id: id,
        tenantId: tenantId,
        productId: productId,
        batchNo: batchNo,
        expiryDate: expiryDate,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

enum SerialStatus { inStock, sold }

/// One physical unit identified by IMEI / serial (phones, electronics).
class ProductSerial {
  const ProductSerial({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.serial,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.saleLineId,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String serial;
  final SerialStatus status;

  /// Set when sold.
  final String? saleLineId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ProductSerial copyWith({
    SerialStatus? status,
    String? Function()? saleLineId,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      ProductSerial(
        id: id,
        tenantId: tenantId,
        productId: productId,
        serial: serial,
        status: status ?? this.status,
        saleLineId: saleLineId != null ? saleLineId() : this.saleLineId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}
