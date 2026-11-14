import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/customer_account.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/pos/presentation/checkout_screen.dart';

/// BUG-7: checkout warns when a credit sale goes over the customer's limit
/// (same rule as the server's CreditLimitExceeded: balance > limit).
void main() {
  final t = DateTime.utc(2026, 11, 1);
  CustomerAccount account({int? limit, int owes = 96000}) => CustomerAccount(
        Customer(id: 'c', tenantId: 't', name: 'ဦးသန်းထွန်း', phone: '', creditLimit: limit, createdAt: t, updatedAt: t),
        [
          DebtEntry(id: 'e', tenantId: 't', customerId: 'c', type: DebtEntryType.adjustment, amount: owes,
              createdAt: t, updatedAt: t),
        ],
      );

  test('no limit → no warning', () => expect(creditLimitWarning(account(), 1000000), isNull));

  test('exactly at the limit is allowed (server: balance > limit)', () {
    expect(creditLimitWarning(account(limit: 100000), 4000), isNull);
  });

  test('over the limit → warning with the limit and the balance after the sale', () {
    final w = creditLimitWarning(account(limit: 100000), 24000);
    expect(w, contains('ကန့်သတ်ချက်'));
    expect(w, contains('100,000'));
    expect(w, contains('120,000'));
  });

  test('already over the limit → still warns for any new credit', () {
    expect(creditLimitWarning(account(limit: 50000), 1), isNotNull);
  });
}
