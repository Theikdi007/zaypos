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

  /// Corrects a wrong payment (BUG-4): appends an adjustment of +amount with
  /// the payment's derived reversal id, as ONE payDebt unit. The payment row
  /// is kept. Reversing the same payment again does nothing (returns null).
  Future<DebtEntry?> reversePayment(DebtEntry payment) {
    if (payment.type != DebtEntryType.payment || payment.deletedAt != null) {
      throw ArgumentError.value(payment.type, 'payment', 'only a live payment can be reversed');
    }
    final id = paymentReversalId(payment.id);
    return uow.run(UnitKind.payDebt, () async {
      final existing = await debt.watchAll().first;
      if (existing.any((e) => e.id == id)) return null;
      final t = nowUtc();
      final e = DebtEntry(
        id: id,
        tenantId: payment.tenantId,
        customerId: payment.customerId,
        type: DebtEntryType.adjustment,
        amount: payment.amount,
        method: payment.method,
        note: '$paymentReversalNote · ${(payment.method ?? PaymentMethod.cash).label}',
        createdAt: t,
        updatedAt: t,
      );
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
      uow: ref.watch(unitOfWorkProvider),
      customers: ref.watch(customerRepositoryProvider),
      debt: ref.watch(debtRepositoryProvider),
    ));
