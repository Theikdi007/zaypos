import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../../products/domain/product.dart';
import '../../sales/data/sales_providers.dart';

/// Which unit of a module product the cashier picked (BUG-2): the IMEI
/// (serialWarranty), the size/colour (variants) or the batch (expiryBatch).
/// [label] is shown after the product name, e.g. "M · အနက်".
typedef ModulePick = ({String? variantId, String? batchId, String? serialId, String label});

/// In-progress sale line. Not persisted. Money = kyats, qty = milli-units.
class CartLine {
  const CartLine({
    required this.key,
    required this.name,
    required this.price,
    required this.qtyMilli,
    this.cost = 0,
    this.productId,
    this.variantId,
    this.batchId,
    this.serialId,
  });

  /// productId for catalog items (plus the variant / batch / IMEI picked),
  /// a fresh id for Quick Sale items.
  final String key;
  final String? productId;
  final String? variantId;
  final String? batchId;

  /// One IMEI = one unit: a serial line's quantity is always 1.
  final String? serialId;
  final String name;
  final int price;

  /// Unit cost snapshot (kyats); 0 for Quick Sale items (cost unknown).
  final int cost;
  final int qtyMilli;

  int get total => Qty.lineTotal(price, qtyMilli);

  CartLine withQty(int milli) => CartLine(
        key: key,
        productId: productId,
        variantId: variantId,
        batchId: batchId,
        serialId: serialId,
        name: name,
        price: price,
        cost: cost,
        qtyMilli: serialId != null ? Qty.scale : milli,
      );
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

  /// All lines of one product (any variant / batch / IMEI), e.g. the POS tile count.
  int qtyOfProduct(String productId) =>
      lines.where((l) => l.productId == productId).fold(0, (a, l) => a + l.qtyMilli);

  /// IMEIs already in the cart (not offered again).
  Set<String> get serialIds => {for (final l in lines) ?l.serialId};

  List<CartLine> get quickLines => lines.where((l) => l.productId == null).toList();

  List<SaleLineDraft> toDrafts() =>
      [
        for (final l in lines)
          (
            productId: l.productId,
            variantId: l.variantId,
            batchId: l.batchId,
            serialId: l.serialId,
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

  /// Adds one unit of [p]. With a [pick] the line names that IMEI / variant /
  /// batch; the same variant or batch again adds to its line, an IMEI is
  /// always its own line of 1 (and is never added twice).
  void addProduct(Product p, {ModulePick? pick}) {
    final key = pick?.serialId != null
        ? 'serial:${pick!.serialId}'
        : pick?.variantId != null
            ? '${p.id}:v:${pick!.variantId}'
            : pick?.batchId != null
                ? '${p.id}:b:${pick!.batchId}'
                : p.id;
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.key == key);
    if (i >= 0) {
      if (lines[i].serialId != null) return; // one IMEI = one unit
      lines[i] = lines[i].withQty(lines[i].qtyMilli + step);
    } else {
      lines.add(CartLine(
        key: key,
        productId: p.id,
        variantId: pick?.variantId,
        batchId: pick?.batchId,
        serialId: pick?.serialId,
        name: pick == null || pick.label.isEmpty ? p.name : '${p.name} · ${pick.label}',
        price: p.price,
        cost: p.cost,
        qtyMilli: step,
      ));
    }
    state = Cart(lines);
  }

  void addQuick(int price, String name) {
    state = Cart([
      ...state.lines,
      CartLine(key: newId(), name: name.trim().isEmpty ? quickSaleName : name.trim(), price: price, qtyMilli: step),
    ]);
  }

  /// Checkout +/− and typed quantity. Any positive quantity is kept (2.5 or
  /// 0.75 when decimalQty is on); zero or less becomes one unit (as in the design).
  void setQty(String key, int qtyMilli) {
    state = Cart([
      for (final l in state.lines) l.key == key ? l.withQty(qtyMilli <= 0 ? step : qtyMilli) : l,
    ]);
  }

  void clear() => state = const Cart([]);
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
