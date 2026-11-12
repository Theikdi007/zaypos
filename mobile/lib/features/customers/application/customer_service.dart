import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/unit_of_work.dart';
import '../../../core/utils/ids.dart';
import '../../sales/domain/sale.dart';
import '../data/customer_repository.dart';
import '../data/debt_repository.dart';
import '../domain/customer.dart';
import '../domain/debt_entry.dart';

/// Customer + debt-ledger commands (each one unit of work).
class CustomerService {
  CustomerService({required this.uow, required this.customers, required this.debt});

  final UnitOfWork uow;
  final CustomerRepository customers;
  final DebtRepository debt;

  /// Adds a customer; a non-zero [openingBalance] (kyats, from the paper
  /// book) is recorded as a ledger adjustment.
  Future<void> create(Customer customer, {int openingBalance = 0}) => uow.run(UnitKind.upsertCustomer, () async {
        await customers.add(customer);
        if (openingBalance != 0) {
          await debt.add(_entry(customer.tenantId, customer.id, DebtEntryType.adjustment, openingBalance,
              note: 'ယခင်အကြွေး'));
        }
      });

  /// PayDebt sheet: records a repayment.
  Future<DebtEntry> recordPayment({
    required String tenantId,
    required String customerId,
    required int amount,
    required PaymentMethod method,
  }) {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'must be positive');
    return uow.run(UnitKind.payDebt, () async {
      final e = _entry(tenantId, customerId, DebtEntryType.payment, amount, method: method);
      await debt.add(e);
      return e;
    });
  }

  DebtEntry _entry(String tenantId, String customerId, DebtEntryType type, int amount,
      {PaymentMethod? method, String? note}) {
    final t = nowUtc();
    return DebtEntry(
      id: newId(),
      tenantId: tenantId,
      customerId: customerId,
      type: type,
      amount: amount,
      method: method,
      note: note,
      createdAt: t,
      updatedAt: t,
    );
  }
}

final customerServiceProvider = Provider<CustomerService>((ref) => CustomerService(
      uow: ref.read(unitOfWorkProvider),
      customers: ref.read(customerRepositoryProvider),
      debt: ref.read(debtRepositoryProvider),
    ));
