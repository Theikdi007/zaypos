import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/drift_unit_of_work.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/customers/data/drift_customer_repository.dart';
import 'package:zaypos_app/features/customers/data/drift_debt_repository.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/inventory/data/drift_stock_repository.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';

import 'drift_helpers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Customer customer(String name) {
    final t = nowUtc();
    return Customer(id: newId(), tenantId: 't', name: name, phone: '09', createdAt: t, updatedAt: t);
  }

  test('a unit writes its rows and exactly one outbox row with all of them', () async {
    final uow = DriftUnitOfWork(db);
    final customers = DriftCustomerRepository(db);
    final debt = DriftDebtRepository(db, deviceId: 'd1');
    final c = customer('ဒေါ်ခင်မာ');
    final t = nowUtc();

    await uow.run(UnitKind.upsertCustomer, () async {
      await customers.add(c);
      await debt.add(DebtEntry(
        id: newId(),
        tenantId: 't',
        customerId: c.id,
        type: DebtEntryType.adjustment,
        amount: 5000,
        note: 'ယခင်အကြွေး',
        createdAt: t,
        updatedAt: t,
      ));
    });

    expect(await db.select(db.customers).get(), hasLength(1));
    expect(await db.select(db.debtEntries).get(), hasLength(1));
    final units = await outbox(db);
    expect(units, hasLength(1));
    final u = units.single;
    expect(u.kind, 'upsertCustomer');
    expect(u.status, OutboxStatus.pending);
    expect(u.attempts, 0);
    final rows = rowsOf(u);
    expect(rows.keys, ['customers', 'debtEntries']);
    expect(rows['customers'].single, containsPair('id', c.id));
    expect(rows['customers'].single, containsPair('name', 'ဒေါ်ခင်မာ'));
    expect(rows['debtEntries'].single, allOf(containsPair('type', 'adjustment'), containsPair('deviceId', 'd1')));
    expect(rows['debtEntries'].single['createdAt'], isoMsMatcher);
  });

  test('a throwing body writes neither rows nor an outbox row', () async {
    final uow = DriftUnitOfWork(db);
    final customers = DriftCustomerRepository(db);
    await expectLater(
      uow.run(UnitKind.upsertCustomer, () async {
        await customers.add(customer('a'));
        throw StateError('disk full');
      }),
      throwsStateError,
    );
    expect(await db.select(db.customers).get(), isEmpty);
    expect(await outbox(db), isEmpty);
  });

  test('a nested unit joins the outer one: one outbox row of the outer kind', () async {
    final uow = DriftUnitOfWork(db);
    final customers = DriftCustomerRepository(db);
    await uow.run(UnitKind.upsertCustomer, () async {
      await customers.add(customer('a'));
      await uow.run(UnitKind.payDebt, () => customers.add(customer('b')));
    });
    final units = await outbox(db);
    expect(units.single.kind, 'upsertCustomer');
    expect(rowsOf(units.single)['customers'], hasLength(2));
  });

  test('a repository write outside a unit of work is refused', () async {
    await expectLater(DriftCustomerRepository(db).add(customer('a')), throwsStateError);
    expect(await db.select(db.customers).get(), isEmpty);
  });

  test('a unit that writes nothing adds no outbox row and does not notify', () async {
    var notified = 0;
    final uow = DriftUnitOfWork(db, onCommitted: (_) => notified++);
    expect(await uow.run(UnitKind.checkout, () async => 42), 42);
    expect(await outbox(db), isEmpty);
    expect(notified, 0);
    await uow.run(UnitKind.upsertCustomer, () => DriftCustomerRepository(db).add(customer('a')));
    expect(notified, 1);
  });

  test('outbox keeps push order across units', () async {
    final uow = DriftUnitOfWork(db);
    final stock = DriftStockRepository(db, deviceId: 'd1');
    for (final kind in [UnitKind.restock, UnitKind.stockAdjust, UnitKind.restock]) {
      await uow.run(kind, () => stock.addAll([restockMovement(tenantId: 't', productId: SeedIds.water, qtyMilli: 1000)]));
    }
    expect((await outbox(db)).map((o) => o.kind), ['restock', 'stockAdjust', 'restock']);
    final seqs = (await outbox(db)).map((o) => o.seq).toList();
    expect(seqs, [...seqs]..sort());
  });

  test('times are stored as unix ms UTC', () async {
    final t = DateTime.utc(2026, 11, 12, 9, 30, 15, 123);
    await DriftUnitOfWork(db).run(UnitKind.upsertCustomer, () => DriftCustomerRepository(db).add(Customer(
          id: 'c1',
          tenantId: 't',
          name: 'n',
          phone: '',
          createdAt: t,
          updatedAt: t,
        )));
    final raw = await db.customSelect('SELECT createdAt FROM customers').getSingle();
    expect(raw.read<int>('createdAt'), t.millisecondsSinceEpoch);
    final row = await db.select(db.customers).getSingle();
    expect(row.createdAt, t);
    expect(row.createdAt.isUtc, isTrue);
    expect(rowsOf((await outbox(db)).single)['customers'].single['createdAt'], '2026-11-12T09:30:15.123Z');
  });

  test('schema: camelCase tables/columns and the §3.1 indexes', () async {
    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(
      tables,
      containsAll([
        'tenants', 'tenantFeatures', 'devices', 'products', 'productVariants', 'productBatches', 'productSerials',
        'stockMovements', 'customers', 'debtEntries', 'sales', 'saleLines', 'payments', 'syncIssues', 'outbox',
        'syncState',
      ]),
    );
    final indexes = (await db.customSelect("SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL").get())
        .map((r) => r.read<String>('sql'))
        .join('\n');
    for (final ix in ['stockMovements (productId)', 'debtEntries (customerId)', 'sales (createdAt)', 'saleLines (saleId)', 'products (barcode)']) {
      expect(indexes.replaceAll('"', ''), contains(ix));
    }
    final saleCols = (await db.customSelect('PRAGMA table_info(sales)').get()).map((r) => r.read<String>('name'));
    expect(saleCols, containsAll(['tenantId', 'customerName', 'voidedAt', 'syncedAt', 'deletedAt']));
    expect(saleCols, isNot(contains('version')));
    expect(db.schemaVersion, 1);
  });

  test('syncState read/write', () async {
    expect(await db.readState('pullCursor'), isNull);
    await db.writeState('pullCursor', '00000000000007D1');
    await db.writeState('pullCursor', '00000000000007D2');
    expect(await db.readState('pullCursor'), '00000000000007D2');
  });

  test('stock movement wire row carries the type name and signed qty', () async {
    await DriftUnitOfWork(db).run(
      UnitKind.stockAdjust,
      () => DriftStockRepository(db, deviceId: 'd1').addAll([
        StockMovement(
          id: 'm1',
          tenantId: 't',
          productId: 'p1',
          type: StockMovementType.adjustment,
          qtyMilli: -1500,
          createdAt: nowUtc(),
          updatedAt: nowUtc(),
        ),
      ]),
    );
    final m = rowsOf((await outbox(db)).single)['stockMovements'].single as Map;
    expect(m['type'], 'adjustment');
    expect(m['qtyMilli'], -1500);
    expect(m['deviceId'], 'd1');
    expect(m['deletedAt'], isNull);
    expect(await (db.select(db.stockMovements)..where((x) => x.id.equals('m1'))).getSingle(), isNotNull);
  });
}

final isoMsMatcher = matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$'));
