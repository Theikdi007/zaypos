import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/customer_account.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

DebtEntry _e(DebtEntryType type, int amount, {DateTime? at, DateTime? deletedAt, String? saleId}) {
  final t = at ?? DateTime.utc(2026, 11, 1);
  return DebtEntry(
    id: '$type$amount$t',
    tenantId: 't',
    customerId: 'c',
    type: type,
    amount: amount,
    saleId: saleId,
    createdAt: t,
    updatedAt: t,
    deletedAt: deletedAt,
  );
}

void main() {
  group('debtBalance', () {
    test('empty ledger owes nothing', () => expect(debtBalance([]), 0));

    test('credit sales add, payments subtract, adjustments are signed', () {
      expect(
        debtBalance([
          _e(DebtEntryType.creditSale, 24000),
          _e(DebtEntryType.creditSale, 18500),
          _e(DebtEntryType.payment, 30000),
          _e(DebtEntryType.creditSale, 39500),
          _e(DebtEntryType.adjustment, -2000),
          _e(DebtEntryType.adjustment, 500),
        ]),
        24000 + 18500 - 30000 + 39500 - 2000 + 500,
      );
    });

    test('soft-deleted entries are ignored', () {
      expect(
        debtBalance([
          _e(DebtEntryType.creditSale, 10000),
          _e(DebtEntryType.payment, 4000, deletedAt: DateTime.utc(2026, 11, 2)),
        ]),
        10000,
      );
    });

    test('overpayment yields a negative balance', () {
      expect(debtBalance([_e(DebtEntryType.creditSale, 5000), _e(DebtEntryType.payment, 6000)]), -1000);
    });
  });

  group('CustomerAccount', () {
    final t = DateTime.utc(2026, 1, 1);
    final customer = Customer(id: 'c', tenantId: 't', name: 'ဦးအောင်ကျော်', phone: '', createdAt: t, updatedAt: t);

    test('void reversal stays in the ledger but is hidden from history', () {
      final a = CustomerAccount(customer, [
        _e(DebtEntryType.creditSale, 24000, saleId: 's1'),
        _e(DebtEntryType.adjustment, -24000, saleId: 's1', at: DateTime.utc(2026, 11, 2)),
      ]);
      expect(a.balance, 0);
      expect(a.history, hasLength(1));
      expect(a.entries, hasLength(2));
    });

    test('overdue after 30 days without activity', () {
      final a = CustomerAccount(customer, [_e(DebtEntryType.creditSale, 1000, at: DateTime.utc(2026, 10, 1))]);
      expect(a.isOverdue(DateTime.utc(2026, 10, 30)), isFalse);
      expect(a.isOverdue(DateTime.utc(2026, 10, 31)), isTrue);
    });

    test('a settled account is never overdue', () {
      final a = CustomerAccount(customer, [
        _e(DebtEntryType.creditSale, 1000, at: DateTime.utc(2026, 1, 1)),
        _e(DebtEntryType.payment, 1000, at: DateTime.utc(2026, 1, 2)),
      ]);
      expect(a.isOverdue(DateTime.utc(2026, 6, 1)), isFalse);
    });
  });

  group('DebtLedgerNotifier (fake repositories)', () {
    test('seeded ဦးအောင်ကျော် balance is the design 52,000', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(customerAccountProvider(SeedIds.aungKyaw))!.balance, 52000);
    });

    test('credit sale + payment update the balance through the ledger', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final sale = c.read(salesProvider.notifier).create(
        method: PaymentMethod.debt,
        lines: [draft(qtyMilli: 2000, price: 3000)],
        customerId: SeedIds.aungKyaw,
      );
      final ledger = c.read(debtLedgerProvider.notifier);
      final credit = ledger.creditSale(SeedIds.aungKyaw, sale);
      expect(credit.type, DebtEntryType.creditSale);
      expect(credit.saleId, sale.id);
      expect(credit.amount, 6000);
      expect(c.read(customerAccountProvider(SeedIds.aungKyaw))!.balance, 58000);

      final pay = ledger.payment(SeedIds.aungKyaw, 20000, PaymentMethod.kbz);
      expect(pay.title, 'ငွေပြန်ဆပ် · KBZPay');
      expect(c.read(customerAccountProvider(SeedIds.aungKyaw))!.balance, 38000);
    });

    test('entries carry tenant id and UUID v7 ids', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final e = c.read(debtLedgerProvider.notifier).payment(SeedIds.aungKyaw, 1000, PaymentMethod.cash);
      expect(e.tenantId, isNotEmpty);
      expect(e.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
