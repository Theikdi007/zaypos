import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../../sales/domain/sale.dart';
import '../domain/customer.dart';
import '../domain/customer_account.dart';
import '../domain/debt_entry.dart';
import 'customer_repository.dart';
import 'debt_repository.dart';

class CustomersNotifier extends Notifier<List<Customer>> {
  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  @override
  List<Customer> build() => _repo.list();

  void add(Customer c) {
    _repo.add(c);
    state = _repo.list();
  }
}

final customersProvider = NotifierProvider<CustomersNotifier, List<Customer>>(CustomersNotifier.new);

/// The debt ledger. All balance changes go through here.
class DebtLedgerNotifier extends Notifier<List<DebtEntry>> {
  DebtRepository get _repo => ref.read(debtRepositoryProvider);

  @override
  List<DebtEntry> build() => _repo.list();

  /// Re-read after a service committed writes.
  void refresh() => state = _repo.list();

  DebtEntry _record(
    String customerId,
    DebtEntryType type,
    int amount, {
    String? saleId,
    String? saleNo,
    PaymentMethod? method,
    String? note,
  }) {
    final t = nowUtc();
    final e = DebtEntry(
      id: newId(),
      tenantId: ref.read(tenantIdProvider),
      customerId: customerId,
      type: type,
      amount: amount,
      saleId: saleId,
      saleNo: saleNo,
      method: method,
      note: note,
      createdAt: t,
      updatedAt: t,
    );
    _repo.add(e);
    state = _repo.list();
    return e;
  }

  /// PayDebt sheet.
  DebtEntry payment(String customerId, int amount, PaymentMethod method) =>
      _record(customerId, DebtEntryType.payment, amount, method: method);

  /// Signed manual/opening adjustment (+ owes more, − owes less).
  DebtEntry adjustment(String customerId, int amount, {String? note, String? saleId}) =>
      _record(customerId, DebtEntryType.adjustment, amount, note: note, saleId: saleId);
}

final debtLedgerProvider = NotifierProvider<DebtLedgerNotifier, List<DebtEntry>>(DebtLedgerNotifier.new);

/// Customers joined with their ledger, in customer order.
final customerAccountsProvider = Provider<List<CustomerAccount>>((ref) {
  final customers = ref.watch(customersProvider);
  final ledger = ref.watch(debtLedgerProvider);
  final byCustomer = <String, List<DebtEntry>>{};
  for (final e in ledger) {
    (byCustomer[e.customerId] ??= []).add(e);
  }
  return [for (final c in customers) CustomerAccount(c, byCustomer[c.id] ?? const [])];
});

final customerAccountProvider = Provider.family<CustomerAccount?, String>((ref, id) {
  for (final a in ref.watch(customerAccountsProvider)) {
    if (a.id == id) return a;
  }
  return null;
});
