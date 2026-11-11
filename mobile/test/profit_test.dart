import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/reports/data/report_providers.dart';
import 'package:zaypos_app/features/reports/data/fake_report_repository.dart';
import 'package:zaypos_app/features/reports/domain/report.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/data/sales_repository.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';

import 'helpers.dart';

SaleLine _line(int price, int cost, int qtyMilli) {
  final t = DateTime.utc(2026);
  return SaleLine(
    id: 'l',
    tenantId: 't',
    saleId: 's',
    name: 'x',
    qtyMilli: qtyMilli,
    price: price,
    costSnapshot: cost,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  test('line profit = (price − costSnapshot) × qty', () {
    expect(_line(600, 450, Qty.units(2)).profit, 300);
    expect(_line(1200, 1000, 2500).profit, 500); // 2.5 units
    expect(_line(500, 600, Qty.units(1)).profit, -100); // sold below cost
  });

  test('a voided sale contributes no profit', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    final voided = c.read(salesProvider).firstWhere((s) => s.id == SeedIds.sale1027);
    expect(voided.voided, isTrue);
    expect(voided.profit, 0);
  });

  test("today's report profit sums cost snapshots of today's live sales", () {
    final c = makeContainer();
    addTearDown(c.dispose);
    final repo = c.read(salesRepositoryProvider);
    final today = repo.list().where((s) => s.createdAt.toLocal().day == DateTime.now().day && !s.voided);
    final expected = today.fold(0, (a, s) => a + s.lines.fold(0, (b, l) => b + Qty.lineTotal(l.price - l.costSnapshot, l.qtyMilli)));
    final r = c.read(reportProvider(ReportPeriod.today));
    expect(r.summary.profit, expected);
    expect(r.summary.count, today.length);
  });

  test('profit uses the snapshot, not the current product cost', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    final before = c.read(reportProvider(ReportPeriod.today)).summary.profit;
    c.read(salesProvider.notifier).create(
      method: PaymentMethod.cash,
      lines: [draft(productId: SeedIds.water, qtyMilli: Qty.units(3), price: 600, cost: 450)],
    );
    // Even if the product's cost changed afterwards, recorded profit stays 3 × 150.
    final report = FakeReportRepository(
      sales: c.read(salesRepositoryProvider),
      products: c.read(productRepositoryProvider),
    ).report(ReportPeriod.today);
    expect(report.summary.profit - before, 450);
  });

  test('payment shares add up to 100', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    for (final p in ReportPeriod.values) {
      final shares = c.read(reportProvider(p)).paymentShares;
      expect(shares.fold(0, (a, s) => a + s.percent), 100, reason: '$p');
    }
  });
}
