import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../../products/domain/product.dart';
import '../../sales/data/sales_providers.dart';

/// In-progress sale line. Not persisted. Money = kyats, qty = milli-units.
class CartLine {
  const CartLine({
    required this.key,
    required this.name,
    required this.price,
    required this.qtyMilli,
    this.cost = 0,
    this.productId,
  });

  /// productId for catalog items, a fresh id for Quick Sale items.
  final String key;
  final String? productId;
  final String name;
  final int price;

  /// Unit cost snapshot (kyats); 0 for Quick Sale items (cost unknown).
  final int cost;
  final int qtyMilli;

  int get total => Qty.lineTotal(price, qtyMilli);

  CartLine withQty(int milli) =>
      CartLine(key: key, productId: productId, name: name, price: price, cost: cost, qtyMilli: milli);
}

class Cart {
  const Cart(this.lines);
  final List<CartLine> lines;

  /// Total quantity in milli-units ("ပစ္စည်း N ခု").
  int get countMilli => lines.fold(0, (a, l) => a + l.qtyMilli);

  /// Kyats.
  int get total => lines.fold(0, (a, l) => a + l.total);
  bool get isEmpty => lines.isEmpty;

  int qtyOf(String key) {
    for (final l in lines) {
      if (l.key == key) return l.qtyMilli;
    }
    return 0;
  }

  List<CartLine> get quickLines => lines.where((l) => l.productId == null).toList();

  List<SaleLineDraft> toDrafts() =>
      [
        for (final l in lines)
          (
            productId: l.productId,
            variantId: null,
            batchId: null,
            serialId: null,
            name: l.name,
            qtyMilli: l.qtyMilli,
            price: l.price,
            cost: l.cost,
          ),
      ];
}

/// Quick Sale lines without a name are labeled with the mode name.
const quickSaleName = 'Quick Sale';

class CartNotifier extends Notifier<Cart> {
  static const step = Qty.scale; // one unit

  @override
  Cart build() => const Cart([]);

  void addProduct(Product p) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.key == p.id);
    if (i >= 0) {
      lines[i] = lines[i].withQty(lines[i].qtyMilli + step);
    } else {
      lines.add(CartLine(key: p.id, productId: p.id, name: p.name, price: p.price, cost: p.cost, qtyMilli: step));
    }
    state = Cart(lines);
  }

  void addQuick(int price, String name) {
    state = Cart([
      ...state.lines,
      CartLine(key: newId(), name: name.trim().isEmpty ? quickSaleName : name.trim(), price: price, qtyMilli: step),
    ]);
  }

  /// Checkout +/−; quantity never drops below one unit (as in the design).
  void setQty(String key, int qtyMilli) {
    state = Cart([
      for (final l in state.lines) l.key == key ? l.withQty(qtyMilli < step ? step : qtyMilli) : l,
    ]);
  }

  void clear() => state = const Cart([]);
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
