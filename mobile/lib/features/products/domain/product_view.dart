import 'product.dart';

/// Read model: product + stock on hand. [stockMilli] is a cached value
/// computed from the stock ledger — it is never stored on [Product].
class ProductView {
  const ProductView(this.product, this.stockMilli, {this.stockTracked = true});

  final Product product;
  final int stockMilli;

  /// False until the product's first restock/adjustment > 0 (e.g. imported
  /// presets): its ledger sum means nothing yet, so it is neither low nor out.
  final bool stockTracked;

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

  /// "Stock မမှတ်ရသေး": shown grey, excluded from every low/out count.
  bool get isUntracked => !stockTracked;

  bool get isOut => stockTracked && stockMilli <= 0;
  bool get isLow => stockTracked && stockMilli > 0 && stockMilli <= product.lowAlertMilli;

  /// Needs reordering: the ONE predicate behind the Dashboard "Stock နည်းနေသည်"
  /// card and the Products "Stock နည်း" filter, so their numbers always match.
  bool get needsRestock => isLow || isOut;
}
