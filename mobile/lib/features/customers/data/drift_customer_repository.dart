import 'package:drift/drift.dart';

import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../../../core/utils/ids.dart';
import '../domain/customer.dart';
import 'customer_repository.dart';

class DriftCustomerRepository implements CustomerRepository {
  DriftCustomerRepository(this.db);
  final AppDatabase db;

  @override
  Stream<List<Customer>> watchAll() => (db.select(db.customers)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.id)]))
      .map(customerFromRow)
      .watch();

  @override
  Stream<Customer?> watchById(String id) =>
      (db.select(db.customers)..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
          .map(customerFromRow)
          .watchSingleOrNull();

  @override
  Future<void> add(Customer customer) async {
    final rec = UnitRecorder.require();
    final row = customerRow(customer);
    await db.into(db.customers).insert(row);
    rec.record(WireTable.customers, customerWire(row));
  }

  @override
  Future<void> update(Customer customer) async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.customers)..where((c) => c.id.equals(customer.id))).getSingleOrNull();
    if (current == null) throw StateError('Unknown customer ${customer.id}');
    // Whole row (cleared fields → NULL, BUG-31); identity / history columns as stored.
    final updated = customerRow(customer).copyWith(
      tenantId: current.tenantId,
      createdAt: current.createdAt,
      updatedAt: nowUtc(),
      deletedAt: Value(current.deletedAt),
    );
    await db.update(db.customers).replace(updated);
    rec.record(WireTable.customers, customerWire(updated));
  }
}
