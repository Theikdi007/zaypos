import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/data/unit_of_work.dart';
import '../core/db/app_database.dart';
import '../core/db/database_provider.dart';
import '../core/db/drift_unit_of_work.dart';
import '../core/features/drift_feature_repository.dart';
import '../core/features/feature_repository.dart';
import '../features/auth/data/session.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/customers/data/debt_repository.dart';
import '../features/customers/data/drift_customer_repository.dart';
import '../features/customers/data/drift_debt_repository.dart';
import '../features/devices/data/device_repository.dart';
import '../features/devices/data/drift_device_repository.dart';
import '../features/inventory/data/drift_stock_repository.dart';
import '../features/inventory/data/stock_repository.dart';
import '../features/products/data/drift_product_repository.dart';
import '../features/products/data/product_repository.dart';
import '../features/reports/data/drift_report_repository.dart';
import '../features/reports/data/report_repository.dart';
import '../features/sales/data/drift_sales_repository.dart';
import '../features/sales/data/sales_repository.dart';
import 'local_bootstrap.dart';

/// Composition root: binds every repository interface and the unit of work
/// to the local Drift database. (Tests use lib/app/fake_overrides.dart.)
List<Override> driftOverrides(AppDatabase db, LocalIdentity me) {
  final sales = DriftSalesRepository(db, deviceId: me.deviceId);
  return [
    appDatabaseProvider.overrideWithValue(db),
    sessionProvider.overrideWith(() => SessionNotifier(tenantId: me.tenantId, shopName: me.shopName)),
    unitOfWorkProvider.overrideWithValue(DriftUnitOfWork(db)),
    productRepositoryProvider.overrideWithValue(DriftProductRepository(db)),
    stockRepositoryProvider.overrideWithValue(DriftStockRepository(db, deviceId: me.deviceId)),
    salesRepositoryProvider.overrideWithValue(sales),
    customerRepositoryProvider.overrideWithValue(DriftCustomerRepository(db)),
    debtRepositoryProvider.overrideWithValue(DriftDebtRepository(db, deviceId: me.deviceId)),
    deviceRepositoryProvider.overrideWithValue(DriftDeviceRepository(db, deviceId: me.deviceId)),
    reportRepositoryProvider.overrideWithValue(DriftReportRepository(db, sales)),
    featureRepositoryProvider.overrideWithValue(DriftFeatureRepository(db, tenantId: me.tenantId)),
  ];
}
