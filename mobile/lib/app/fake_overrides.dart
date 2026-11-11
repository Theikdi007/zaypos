import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/data/unit_of_work.dart';
import '../features/auth/data/session.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/customers/data/debt_repository.dart';
import '../features/customers/data/fake_customer_repository.dart';
import '../features/customers/data/fake_debt_repository.dart';
import '../features/devices/data/device_repository.dart';
import '../features/devices/data/fake_device_repository.dart';
import '../features/inventory/data/fake_stock_repository.dart';
import '../features/inventory/data/stock_repository.dart';
import '../features/products/data/fake_product_repository.dart';
import '../features/products/data/product_repository.dart';
import '../features/reports/data/fake_report_repository.dart';
import '../features/reports/data/report_repository.dart';
import '../features/sales/data/fake_sales_repository.dart';
import '../features/sales/data/sales_repository.dart';
import 'fake_database.dart';

/// A fake database filled with the design's sample data.
FakeDatabase seedFakeDatabase(String tenantId) => FakeDatabase()
  ..products.addAll(seedProducts(tenantId))
  ..stock.addAll(seedStock(tenantId))
  ..sales.addAll(seedSales(tenantId))
  ..customers.addAll(seedCustomers(tenantId))
  ..debt.addAll(seedDebt(tenantId))
  ..devices.add(seedDevice(tenantId));

final fakeDatabaseProvider = Provider<FakeDatabase>((ref) => seedFakeDatabase(ref.read(tenantIdProvider)));

/// Composition root: binds every repository interface (and the unit of
/// work) to the fake database. Swap these for Drift/API implementations
/// later — nothing else changes.
final List<Override> fakeRepositoryOverrides = [
  unitOfWorkProvider.overrideWith((ref) => FakeUnitOfWork(ref.read(fakeDatabaseProvider))),
  productRepositoryProvider.overrideWith((ref) => FakeProductRepository(ref.read(fakeDatabaseProvider))),
  stockRepositoryProvider.overrideWith((ref) => FakeStockRepository(ref.read(fakeDatabaseProvider))),
  salesRepositoryProvider.overrideWith((ref) => FakeSalesRepository(ref.read(fakeDatabaseProvider))),
  customerRepositoryProvider.overrideWith((ref) => FakeCustomerRepository(ref.read(fakeDatabaseProvider))),
  debtRepositoryProvider.overrideWith((ref) => FakeDebtRepository(ref.read(fakeDatabaseProvider))),
  deviceRepositoryProvider.overrideWith((ref) {
    final db = ref.read(fakeDatabaseProvider);
    return FakeDeviceRepository(db, deviceId: db.devices.first.id);
  }),
  reportRepositoryProvider.overrideWith((ref) => FakeReportRepository(ref.read(fakeDatabaseProvider))),
];
