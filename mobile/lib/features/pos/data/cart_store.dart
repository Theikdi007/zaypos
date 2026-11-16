import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../domain/cart.dart';

/// BUG-57: the open cart is kept in the local database, so it survives Android
/// killing the app in the background (e.g. while the cashier checks a payment
/// in KBZPay or Wave). It is stored in the key/value state table, per shop;
/// a cart of another shop is never restored.
abstract final class CartStateKeys {
  static const openCart = 'pos.openCart';
}

/// The cart as saved: the shop it belongs to and its lines.
typedef SavedCart = ({String tenantId, Cart cart});

abstract class CartStore {
  Future<void> save(String tenantId, Cart cart);
}

class DriftCartStore implements CartStore {
  DriftCartStore(this.db);
  final AppDatabase db;

  @override
  Future<void> save(String tenantId, Cart cart) => db.writeState(CartStateKeys.openCart, encodeCart(tenantId, cart));
}

/// Reads the saved cart before `runApp` (null when none or unreadable).
Future<SavedCart?> loadOpenCart(AppDatabase db) async => decodeCart(await db.readState(CartStateKeys.openCart));

String encodeCart(String tenantId, Cart cart) => jsonEncode({
      'v': 1,
      'tenantId': tenantId,
      'lines': [
        for (final l in cart.lines)
          {
            'key': l.key,
            'productId': l.productId,
            'variantId': l.variantId,
            'batchId': l.batchId,
            'serialId': l.serialId,
            'name': l.name,
            'price': l.price,
            'cost': l.cost,
            'qtyMilli': l.qtyMilli,
          },
      ],
    });

SavedCart? decodeCart(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final m = jsonDecode(json) as Map<String, dynamic>;
    if (m['v'] != 1) return null;
    final lines = [
      for (final l in (m['lines'] as List).cast<Map<String, dynamic>>())
        CartLine(
          key: l['key'] as String,
          productId: l['productId'] as String?,
          variantId: l['variantId'] as String?,
          batchId: l['batchId'] as String?,
          serialId: l['serialId'] as String?,
          name: l['name'] as String,
          price: l['price'] as int,
          cost: l['cost'] as int,
          qtyMilli: l['qtyMilli'] as int,
        ),
    ];
    return (tenantId: m['tenantId'] as String, cart: Cart(lines));
  } on Object {
    return null; // a broken entry is dropped, never a crash at start
  }
}

/// Where the cart is saved; null = memory only (tests, demo). Bound in main.
final cartStoreProvider = Provider<CartStore?>((_) => null);

/// The cart read at start ([loadOpenCart]), handed out once: after it is
/// restored (or dropped for another shop) a later rebuild starts empty.
class CartRestore {
  CartRestore(this._saved);
  SavedCart? _saved;

  SavedCart? take() {
    final s = _saved;
    _saved = null;
    return s;
  }
}

/// Bound in main from [loadOpenCart].
final initialCartProvider = Provider<CartRestore>((_) => CartRestore(null));
