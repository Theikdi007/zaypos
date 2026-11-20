import '../../../core/text/myanmar_text.dart';

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

  /// Kyats. null = unknown (the owner left ဝယ်ဈေး empty); 0 = really costs nothing (BUG-61).
  final int? cost;

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

  /// BUG-52: name, category and unit with Zawgyi converted to Unicode; the
  /// avatar initial follows the converted name.
  Product normalizedText() {
    final n = normalizeMyanmar(name), c = normalizeMyanmar(category), u = normalizeMyanmar(unit);
    if (identical(n, name) && identical(c, category) && identical(u, unit)) return this;
    return copyWith(
      name: n,
      category: c,
      unit: u,
      initial: identical(n, name) || n.isEmpty ? initial : String.fromCharCode(n.runes.first),
    );
  }

  Product copyWith({
    String? name,
    int? Function()? cost,
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
        cost: cost != null ? cost() : this.cost,
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

  /// BUG-52: size and colour with Zawgyi converted to Unicode.
  ProductVariant normalizedText() {
    final s = normalizeMyanmar(size), c = normalizeMyanmar(color);
    if (identical(s, size) && identical(c, color)) return this;
    return ProductVariant(
      id: id,
      tenantId: tenantId,
      productId: productId,
      size: s,
      color: c,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }

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
