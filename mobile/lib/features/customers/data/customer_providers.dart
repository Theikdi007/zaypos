import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/async_combine.dart';
import '../domain/customer.dart';
import '../domain/customer_account.dart';
import '../domain/debt_entry.dart';
import 'customer_repository.dart';
import 'debt_repository.dart';

final customersProvider = StreamProvider<List<Customer>>((ref) => ref.watch(customerRepositoryProvider).watchAll());

/// The debt ledger (live).
final debtLedgerProvider = StreamProvider<List<DebtEntry>>((ref) => ref.watch(debtRepositoryProvider).watchAll());

/// Balance per customer (SUM over the debt ledger, computed by the database).
final debtBalancesProvider =
    StreamProvider<Map<String, int>>((ref) => ref.watch(debtRepositoryProvider).watchBalances());

/// Customers joined with their ledger and balance, in customer order.
final customerAccountsProvider = Provider<AsyncValue<List<CustomerAccount>>>((ref) {
  final customers = ref.watch(customersProvider);
  final ledger = ref.watch(debtLedgerProvider);
  final balances = ref.watch(debtBalancesProvider);
  final ready = allReady([customers, ledger, balances]);
  if (ready.hasError) return AsyncError(ready.error!, ready.stackTrace ?? StackTrace.empty);
  if (!ready.hasValue) return const AsyncLoading();
  final byCustomer = <String, List<DebtEntry>>{};
  for (final e in ledger.requireValue) {
    (byCustomer[e.customerId] ??= []).add(e);
  }
  final balance = balances.requireValue;
  return AsyncData([
    for (final Customer c in customers.requireValue)
      CustomerAccount(c, byCustomer[c.id] ?? const [], storedBalance: balance[c.id] ?? 0),
  ]);
});

final customerAccountProvider = Provider.family<AsyncValue<CustomerAccount?>, String>(
  (ref, id) => ref.watch(customerAccountsProvider).whenData((all) => all.where((a) => a.id == id).firstOrNull),
);
