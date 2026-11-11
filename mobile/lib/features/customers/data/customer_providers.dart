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

/// Customers joined with their ledger, in customer order.
final customerAccountsProvider = Provider<AsyncValue<List<CustomerAccount>>>((ref) => combineAsync(
      ref.watch(customersProvider),
      ref.watch(debtLedgerProvider),
      (List<Customer> customers, List<DebtEntry> ledger) {
        final byCustomer = <String, List<DebtEntry>>{};
        for (final e in ledger) {
          (byCustomer[e.customerId] ??= []).add(e);
        }
        return [for (final c in customers) CustomerAccount(c, byCustomer[c.id] ?? const [])];
      },
    ));

final customerAccountProvider = Provider.family<AsyncValue<CustomerAccount?>, String>(
  (ref, id) => ref.watch(customerAccountsProvider).whenData((all) => all.where((a) => a.id == id).firstOrNull),
);
