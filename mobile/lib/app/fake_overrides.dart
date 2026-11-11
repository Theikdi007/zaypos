import 'package:flutter_riverpod/misc.dart' show Override;

import '../features/auth/data/session.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/customers/data/debt_repository.dart';
import '../features/customers/data/fake_customer_repository.dart';
import '../features/customers/data/fake_debt_repository.dart';
import '../features/products/data/fake_product_repository.dart';
import '../features/products/data/product_repository.dart';
import '../features/reports/data/fake_report_repository.dart';
import '../features/reports/data/report_repository.dart';
import '../features/sales/data/fake_sales_repository.dart';
import '../features/sales/data/sales_repository.dart';

/// Composition root: binds every repository interface to its fake.
/// Swap these for API/Drift implementations later — nothing else changes.
final List<Override> fakeRepositoryOverrides = [
  productRepositoryProvider.overrideWith((ref) => FakeProductRepository(tenantId: ref.read(tenantIdProvider))),
  salesRepositoryProvider.overrideWith((ref) => FakeSalesRepository(tenantId: ref.read(tenantIdProvider))),
  customerRepositoryProvider.overrideWith((ref) => FakeCustomerRepository(tenantId: ref.read(tenantIdProvider))),
  debtRepositoryProvider.overrideWith((ref) => FakeDebtRepository(tenantId: ref.read(tenantIdProvider))),
  reportRepositoryProvider.overrideWith((ref) => FakeReportRepository()),
];
