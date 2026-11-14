import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/pin_reset_screen.dart';
import '../../features/devices/presentation/devices_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/unlock_screen.dart';
import '../../features/customers/presentation/add_customer_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/customers/presentation/debt_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/pos/presentation/checkout_screen.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/products/presentation/add_product_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/reports/presentation/report_screen.dart';
import '../../features/sales/presentation/sale_detail_screen.dart';
import '../../features/sales/presentation/sale_receipt_screen.dart';
import '../../features/sales/presentation/sales_history_screen.dart';
import '../../features/settings/presentation/settings_features_screen.dart';
import '../../features/sync/presentation/first_sync_screen.dart';
import '../../features/sync/presentation/rejected_unit_screen.dart';
import '../../features/sync/presentation/sync_review_screen.dart';
import '../sync/sync_providers.dart';
import 'app_shell.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Where [status] allows [location] to go; null = stay.
/// Signed out → Login/Register only. Locked → PIN unlock only. Unlocked but
/// the shop not downloaded yet → the first-download screen only (§5.4).
/// Unlocked → the app (Register stays reachable for changing the template).
String? authRedirect(AuthStatus status, String location, {bool firstSyncDone = true}) {
  final public = location == Routes.login || location == Routes.register || location == Routes.pinReset;
  return switch (status) {
    AuthStatus.signedOut => public ? null : Routes.login,
    // A locked-out owner can reset the PIN by SMS from the unlock screen.
    AuthStatus.locked => location == Routes.unlock || location == Routes.pinReset ? null : Routes.unlock,
    AuthStatus.unlocked when !firstSyncDone => location == Routes.firstSync ? null : Routes.firstSync,
    AuthStatus.unlocked =>
      location == Routes.login || location == Routes.unlock || location == Routes.firstSync ? Routes.dashboard : null,
  };
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the auth status or first-download state changes.
  final gate = ValueNotifier((ref.read(authControllerProvider).status, ref.read(firstSyncDoneProvider)));
  ref.listen(authControllerProvider, (_, next) => gate.value = (next.status, gate.value.$2));
  ref.listen(firstSyncDoneProvider, (_, done) => gate.value = (gate.value.$1, done));
  ref.onDispose(gate.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.dashboard,
    refreshListenable: gate,
    redirect: (_, s) => authRedirect(gate.value.$1, s.matchedLocation, firstSyncDone: gate.value.$2),
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.unlock, builder: (_, _) => const UnlockScreen()),
      GoRoute(path: Routes.firstSync, builder: (_, _) => const FirstSyncScreen()),
      GoRoute(path: Routes.devices, builder: (_, _) => const DevicesScreen()),
      GoRoute(path: Routes.pinReset, builder: (_, _) => const PinResetScreen()),
      GoRoute(
        path: Routes.syncReview,
        builder: (_, _) => const SyncReviewScreen(),
        routes: [
          GoRoute(
            path: 'unit/:seq',
            builder: (_, s) => RejectedUnitScreen(seq: int.parse(s.pathParameters['seq']!)),
          ),
        ],
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, s) => RegisterScreen(
          initialStep: int.tryParse(s.uri.queryParameters['step'] ?? '') ?? 1,
        ),
      ),
      GoRoute(path: Routes.pos, builder: (_, _) => const PosScreen()),
      GoRoute(path: Routes.checkout, builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: Routes.settingsFeatures,
        builder: (_, _) => const SettingsFeaturesScreen(),
      ),
      GoRoute(
        path: Routes.sales,
        builder: (_, _) => const SalesHistoryScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => SaleDetailScreen(id: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'receipt',
                builder: (_, s) =>
                    SaleReceiptScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (_, _) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.products,
              builder: (_, s) =>
                  ProductsScreen(initialFilter: ProductsScreen.filterFromQuery(s.uri.queryParameters['filter'])),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const AddProductScreen(),
                ),
                GoRoute(
                  path: ':id/edit',
                  parentNavigatorKey: _rootKey,
                  builder: (_, s) => EditProductScreen(productId: s.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.customers,
              builder: (_, _) => const CustomersScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const AddCustomerScreen(),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, s) => DebtScreen(id: s.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.reports,
              builder: (_, _) => const ReportScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});
