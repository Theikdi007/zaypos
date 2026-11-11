/// Catalog item. Money = int kyats; quantities = int milli-units (see Qty).
class Product {
  const Product({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.cost,
    required this.price,
    required this.stockMilli,
    required this.category,
    required this.tint,
    required this.initial,
    required this.createdAt,
    required this.updatedAt,
    this.unit = '',
    this.barcode,
    this.wholesalePrice,
    this.lowAlertMilli = 5000,
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

  final int stockMilli;
  final int lowAlertMilli;
  final String category;
  final String unit;
  final String? barcode;

  /// ARGB tile color.
  final int tint;
  final String initial;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isOut => stockMilli <= 0;
  bool get isLow => stockMilli > 0 && stockMilli <= lowAlertMilli;

  Product copyWith({
    String? name,
    int? cost,
    int? price,
    int? Function()? wholesalePrice,
    int? stockMilli,
    int? lowAlertMilli,
    String? category,
    String? unit,
    String? Function()? barcode,
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
        stockMilli: stockMilli ?? this.stockMilli,
        lowAlertMilli: lowAlertMilli ?? this.lowAlertMilli,
        category: category ?? this.category,
        unit: unit ?? this.unit,
        barcode: barcode != null ? barcode() : this.barcode,
        tint: tint ?? this.tint,
        initial: initial ?? this.initial,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}

/// Size × color variant of a product (TenantFeatures.variants).
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.size,
    required this.color,
    required this.stockMilli,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String size;
  final String color;
  final int stockMilli;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// "M · အနက်"
  String get label => '$size · $color';

  ProductVariant copyWith({int? stockMilli, DateTime? updatedAt, DateTime? Function()? deletedAt}) => ProductVariant(
        id: id,
        tenantId: tenantId,
        productId: productId,
        size: size,
        color: color,
        stockMilli: stockMilli ?? this.stockMilli,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );
}
