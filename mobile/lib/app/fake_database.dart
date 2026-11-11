import 'dart:async';

import '../core/data/unit_of_work.dart';
import '../features/customers/domain/customer.dart';
import '../features/customers/domain/debt_entry.dart';
import '../features/devices/domain/device.dart';
import '../features/inventory/domain/stock_movement.dart';
import '../features/products/domain/product.dart';
import '../features/products/domain/product_modules.dart';
import '../features/sales/domain/sale.dart';

enum FakeTable { products, variants, batches, serials, stock, sales, customers, debt, devices }

/// In-memory stand-in for the local (Drift) database: one object holding
/// every table, so a transaction can cover writes from several
/// repositories. Rows are immutable, so a snapshot is a shallow copy.
///
/// Reactive like Drift: writers call [touch]; [watch] re-runs its query
/// whenever a watched table changes. Inside a transaction, notifications
/// are held until commit (and dropped on rollback), so listeners never see
/// half-written state.
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
  final _changes = StreamController<Set<FakeTable>>.broadcast();
  final _pending = <FakeTable>{};

  /// Marks [tables] as changed (call after every write).
  void touch(Set<FakeTable> tables) {
    if (_depth > 0) {
      _pending.addAll(tables);
    } else {
      _changes.add(tables);
    }
  }

  /// Emits [query]'s result now and again whenever one of [tables] changes.
  Stream<T> watch<T>(Set<FakeTable> tables, T Function() query) {
    StreamSubscription<Set<FakeTable>>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(query());
        sub = _changes.stream.where((changed) => changed.any(tables.contains)).listen((_) {
          if (!controller.isClosed) controller.add(query());
        });
      },
      // Don't hand the inner cancel future back: `Stream.first` waits on it.
      onCancel: () {
        sub?.cancel();
      },
    );
    return controller.stream;
  }

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
      final result = await body();
      _depth--;
      if (_pending.isNotEmpty) {
        _changes.add({..._pending});
        _pending.clear();
      }
      return result;
    } catch (_) {
      _depth--;
      _pending.clear();
      for (final r in restore) {
        r();
      }
      rethrow;
    }
  }
}

class FakeUnitOfWork implements UnitOfWork {
  FakeUnitOfWork(this.db);
  final FakeDatabase db;

  @override
  Future<T> run<T>(Future<T> Function() body) => db.transaction(body);
}
