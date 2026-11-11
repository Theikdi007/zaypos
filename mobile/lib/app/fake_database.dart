import '../core/data/unit_of_work.dart';
import '../features/customers/domain/customer.dart';
import '../features/customers/domain/debt_entry.dart';
import '../features/devices/domain/device.dart';
import '../features/inventory/domain/stock_movement.dart';
import '../features/products/domain/product.dart';
import '../features/products/domain/product_modules.dart';
import '../features/sales/domain/sale.dart';

/// In-memory stand-in for the local (Drift) database: one object holding
/// every table, so a transaction can cover writes from several
/// repositories. Rows are immutable, so a snapshot is a shallow copy.
class FakeDatabase {
  final products = <Product>[];
  final variants = <ProductVariant>[];
  final batches = <ProductBatch>[];
  final serials = <ProductSerial>[];
  final stock = <StockMovement>[];
  final sales = <Sale>[];
  final customers = <Customer>[];
  final debt = <DebtEntry>[];
  final devices = <Device>[];

  int _depth = 0;

  /// Typed snapshot of one table; calling the result restores it.
  static void Function() _snapshot<T>(List<T> table) {
    final copy = List<T>.of(table);
    return () => table
      ..clear()
      ..addAll(copy);
  }

  /// All-or-nothing: restores every table if [body] throws.
  Future<T> transaction<T>(Future<T> Function() body) async {
    if (_depth > 0) return body(); // nested: join the outer transaction
    final restore = [
      _snapshot(products),
      _snapshot(variants),
      _snapshot(batches),
      _snapshot(serials),
      _snapshot(stock),
      _snapshot(sales),
      _snapshot(customers),
      _snapshot(debt),
      _snapshot(devices),
    ];
    _depth++;
    try {
      return await body();
    } catch (_) {
      for (final r in restore) {
        r();
      }
      rethrow;
    } finally {
      _depth--;
    }
  }
}

class FakeUnitOfWork implements UnitOfWork {
  FakeUnitOfWork(this.db);
  final FakeDatabase db;

  @override
  Future<T> run<T>(Future<T> Function() body) => db.transaction(body);
}
