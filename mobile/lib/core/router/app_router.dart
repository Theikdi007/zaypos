import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
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
import 'app_shell.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.login,
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
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
              builder: (_, _) => const ProductsScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const AddProductScreen(),
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
