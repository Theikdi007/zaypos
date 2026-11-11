/// Catalog item. Money = int kyats; quantities = int milli-units (see Qty).
class Product {
  const Product({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.cost,
    required this.price,
    required this.category,
    required this.tint,
    required this.initial,
    required this.createdAt,
    required this.updatedAt,
    this.unit = '',
    this.barcode,
    this.wholesalePrice,
    this.lowAlertMilli = 5000,
    this.warrantyMonths,
    this.expiryAlertDays,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String name;

  /// Kyats.
  final int cost;

  /// Kyats.
  final int price;

  /// Kyats (contractor / wholesale; TenantFeatures.quotation).
  final int? wholesalePrice;

  /// Low-stock alert threshold (milli-units). Stock itself lives in the
  /// stock ledger (StockMovement), not here.
  final int lowAlertMilli;
  final String category;
  final String unit;
  final String? barcode;

  /// Warranty printed on the receipt (TenantFeatures.serialWarranty); null = none.
  final int? warrantyMonths;

  /// Warn this many days before a batch expires (TenantFeatures.expiryBatch).
  final int? expiryAlertDays;

  /// ARGB tile color.
  final int tint;
  final String initial;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Product copyWith({
    String? name,
    int? cost,
    int? price,
    int? Function()? wholesalePrice,
    int? lowAlertMilli,
    String? category,
    String? unit,
    String? Function()? barcode,
    int? Function()? warrantyMonths,
    int? Function()? expiryAlertDays,
    int? tint,
    String? initial,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Product(
        id: id,
        tenantId: tenantId,
        name: name ?? this.name,
        cost: cost ?? this.cost,
        price: price ?? this.price,
        wholesalePrice: wholesalePrice != null ? wholesalePrice() : this.wholesalePrice,
        lowAlertMilli: lowAlertMilli ?? this.lowAlertMilli,
        category: category ?? this.category,
        unit: unit ?? this.unit,
        barcode: barcode != null ? barcode() : this.barcode,
        warrantyMonths: warrantyMonths != null ? warrantyMonths() : this.warrantyMonths,
        expiryAlertDays: expiryAlertDays != null ? expiryAlertDays() : this.expiryAlertDays,
        tint: tint ?? this.tint,
        initial: initial ?? this.initial,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// Size × color variant of a product (TenantFeatures.variants). Its stock
/// is the sum of StockMovements with this variantId.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.size,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String size;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// "M · အနက်"
  String get label => '$size · $color';

  ProductVariant copyWith({DateTime? updatedAt, DateTime? Function()? deletedAt}) => ProductVariant(
        id: id,
        tenantId: tenantId,
        productId: productId,
        size: size,
        color: color,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}
