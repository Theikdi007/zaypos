import 'product.dart';

/// Read model: product + stock on hand. [stockMilli] is a cached value
/// computed from the stock ledger — it is never stored on [Product].
class ProductView {
  const ProductView(this.product, this.stockMilli);

  final Product product;
  final int stockMilli;

  String get id => product.id;
  String get name => product.name;
  int get cost => product.cost;
  int get price => product.price;
  String get category => product.category;
  int get tint => product.tint;
  String get initial => product.initial;

  /// No selling price yet (e.g. imported from the preset catalog): must not be
  /// sold at 0 Ks — POS asks for the price first.
  bool get needsPrice => product.price <= 0;

  bool get isOut => stockMilli <= 0;
  bool get isLow => stockMilli > 0 && stockMilli <= product.lowAlertMilli;
}
