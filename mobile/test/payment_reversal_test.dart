import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/domain/customer_account.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';

/// Current account from the live providers (waits for the streams).
Future<CustomerAccount?> _account(ProviderContainer c, String id) async {
  final sub = c.listen(customerAccountProvider(id), (_, _) {});
  try {
    for (var i = 0; i < 100; i++) {
      final v = c.read(customerAccountProvider(id));
      if (v.hasValue && !v.isLoading) return v.requireValue;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('account $id never loaded');
  } finally {
    sub.close();
  }
}

/// BUG-4: a wrong debt payment is corrected by a reversal row (never deleted),
/// at most once per payment.
void main() {
  setUpAll(loadAppFonts);

  test('derived reversal id: same payment → same id; different payments → different ids', () {
    final a = newId(), b = newId();
    expect(paymentReversalId(a), paymentReversalId(a));
    expect(paymentReversalId(a), isNot(paymentReversalId(b)));
    expect(paymentReversalId(a), isNot(a));
  });

  test('reversePayment: +amount adjustment, payment kept, balance restored, second reverse is a no-op', () async {
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    final svc = c.read(customerServiceProvider);
    final db = c.read(fakeDatabaseProvider);
    final tenantId = c.read(tenantIdProvider);
    final before = db.debt.where((e) => e.customerId == SeedIds.aungKyaw).toList();
    final balance0 = debtBalance(before);

    final pay = await svc.recordPayment(
        tenantId: tenantId, customerId: SeedIds.aungKyaw, amount: 20000, method: PaymentMethod.kbz);
    final rev = await svc.reversePayment(pay);

    expect(rev, isNotNull);
    expect((rev!.id, rev.type, rev.amount, rev.customerId), (paymentReversalId(pay.id), DebtEntryType.adjustment, 20000, SeedIds.aungKyaw));
    expect(rev.title, contains('ပြန်ပယ်'));
    expect(db.debt.any((e) => e.id == pay.id && e.deletedAt == null), isTrue, reason: 'never deleted');
    expect(debtBalance(db.debt.where((e) => e.customerId == SeedIds.aungKyaw)), balance0);

    final kinds = (c.read(unitOfWorkProvider) as FakeUnitOfWork).kinds;
    expect(kinds.last, UnitKind.payDebt);
    final n = db.debt.length;
    expect(await svc.reversePayment(pay), isNull);
    expect(db.debt.length, n, reason: 'reversed once only');

    final acct = await _account(c, SeedIds.aungKyaw);
    final p = acct!.entries.firstWhere((e) => e.id == pay.id);
    expect((acct.isReversed(p), acct.canReverse(p)), (true, false));
    expect(acct.history.any((e) => e.id == rev.id), isTrue, reason: 'the reversal is visible in the history');

    expect(() => svc.reversePayment(rev), throwsArgumentError, reason: 'only payments are reversible');
  });

  test('Drift: the reversal is ONE payDebt unit with one debtEntries row', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = nowUtc();
    final svc = c.read(customerServiceProvider);
    final customer = Customer(
        id: newId(), tenantId: shop.tenantId, name: 'ဒေါ်မြ', phone: '09123456789', createdAt: t, updatedAt: t);
    await svc.create(customer, openingBalance: 30000);
    final pay = await svc.recordPayment(
        tenantId: shop.tenantId, customerId: customer.id, amount: 10000, method: PaymentMethod.cash);
    await db.delete(db.outbox).go();

    await svc.reversePayment(pay);
    await svc.reversePayment(pay);

    final unit = (await outbox(db)).single;
    expect(unit.kind, 'payDebt');
    final row = (SyncStore.rowsOf(unit)[WireTable.debtEntries] as List).single as Map;
    expect((row['id'], row['type'], row['amount'], row['customerId']),
        (paymentReversalId(pay.id), 'adjustment', 10000, customer.id));
    final acct = await _account(c, customer.id);
    expect(acct!.balance, 30000);
  });

  testWidgets('history: tap a payment → confirm → reversal row; the payment shows "ပြန်ပယ်ပြီး"', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: fakeRepositoryOverrides);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final pay = await c.read(customerServiceProvider).recordPayment(
        tenantId: c.read(tenantIdProvider), customerId: SeedIds.aungKyaw, amount: 7000, method: PaymentMethod.cash);
    final owed = debtBalance(c.read(fakeDatabaseProvider).debt.where((e) => e.customerId == SeedIds.aungKyaw));
    c.read(appRouterProvider).go(Routes.customer(SeedIds.aungKyaw));
    await tester.pumpAndSettle();

    await tester.tap(find.text('− 7,000').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('ကို ပြန်ပယ်မလား'), findsOneWidget);
    await tester.tap(find.text('ပြန်ပယ်မယ်'));
    await tester.pumpAndSettle();

    final debt = c.read(fakeDatabaseProvider).debt;
    expect(debt.any((e) => e.id == paymentReversalId(pay.id)), isTrue);
    expect(debtBalance(debt.where((e) => e.customerId == SeedIds.aungKyaw)), owed + 7000);
    expect(find.textContaining('ပြန်ပယ်ပြီး'), findsOneWidget);
    expect(find.textContaining('ငွေပြန်ဆပ် ပြန်ပယ်'), findsOneWidget);
  });
}
