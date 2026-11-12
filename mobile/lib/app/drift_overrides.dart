import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/data/unit_of_work.dart';
import '../core/db/app_database.dart';
import '../core/db/database_provider.dart';
import '../core/db/drift_unit_of_work.dart';
import '../core/features/drift_feature_repository.dart';
import '../core/features/feature_repository.dart';
import '../core/storage/secure_store.dart';
import '../features/auth/data/boot_state.dart';
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

/// Composition root: binds every repository interface and the unit of work
/// to the local Drift database. Repositories that stamp the device or tenant
/// rebuild when the session changes (sign-in, sign-out).
/// (Tests use lib/app/fake_overrides.dart.)
List<Override> driftOverrides(AppDatabase db, BootState boot, SecureStore store) => [
      appDatabaseProvider.overrideWithValue(db),
      bootStateProvider.overrideWithValue(boot),
      secureStoreProvider.overrideWithValue(store),
      unitOfWorkProvider.overrideWithValue(DriftUnitOfWork(db)),
      productRepositoryProvider.overrideWithValue(DriftProductRepository(db)),
      stockRepositoryProvider.overrideWith((ref) => DriftStockRepository(db, deviceId: ref.watch(deviceIdProvider))),
      salesRepositoryProvider.overrideWith((ref) => DriftSalesRepository(db, deviceId: ref.watch(deviceIdProvider))),
      customerRepositoryProvider.overrideWithValue(DriftCustomerRepository(db)),
      debtRepositoryProvider.overrideWith((ref) => DriftDebtRepository(db, deviceId: ref.watch(deviceIdProvider))),
      deviceRepositoryProvider.overrideWith((ref) => DriftDeviceRepository(db, deviceId: ref.watch(deviceIdProvider))),
      reportRepositoryProvider.overrideWith(
          (ref) => DriftReportRepository(db, DriftSalesRepository(db, deviceId: ref.watch(deviceIdProvider)))),
      featureRepositoryProvider.overrideWith((ref) => DriftFeatureRepository(db, tenantId: ref.watch(tenantIdProvider))),
    ];
