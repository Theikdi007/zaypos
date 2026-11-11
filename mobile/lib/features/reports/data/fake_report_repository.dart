import '../../../core/utils/myanmar.dart';
import '../../../core/utils/qty.dart';
import '../../products/data/product_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../domain/report.dart';
import 'report_repository.dart';

/// Computes reports from the (fake) sales store, the way a Drift query
/// would. Profit uses each line's costSnapshot, never the current cost.
class FakeReportRepository implements ReportRepository {
  FakeReportRepository({required this.sales, required this.products});

  final SalesRepository sales;
  final ProductRepository products;

  static const _weekday = {1: 'တနင်္လာ', 2: 'အင်္ဂါ', 3: 'ဗုဒ္ဓ', 4: 'ကြာ', 5: 'သော', 6: 'စနေ', 7: 'တနင်္ဂ'};

  @override
  ReportSnapshot report(ReportPeriod period, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final today = DateTime(n.year, n.month, n.day);
    final from = switch (period) {
      ReportPeriod.today => today,
      ReportPeriod.week => today.subtract(const Duration(days: 6)),
      ReportPeriod.month => DateTime(n.year, n.month, 1),
    };
    final live = sales.list().where((s) => !s.voided).toList();
    List<Sale> between(DateTime a, DateTime b) =>
        live.where((s) => !s.createdAt.toLocal().isBefore(a) && s.createdAt.toLocal().isBefore(b)).toList();
    final tomorrow = today.add(const Duration(days: 1));
    final inPeriod = between(from, tomorrow);

    final range = switch (period) {
      ReportPeriod.today => 'ယနေ့',
      ReportPeriod.week => '၇ ရက်',
      ReportPeriod.month => '${mmMonths[n.month - 1]} ၁–${mmDigits(n.day)}',
    };
    final summary = PeriodSummary(
      range: range,
      sales: _sum(inPeriod, (s) => s.total),
      profit: _sum(inPeriod, (s) => s.profit),
      count: inPeriod.length,
    );

    final days = [
      for (var i = 6; i >= 0; i--)
        () {
          final d = today.subtract(Duration(days: i));
          return DaySales(i == 0 ? 'ယနေ့' : _weekday[d.weekday]!, _sum(between(d, d.add(const Duration(days: 1))), (s) => s.total));
        }(),
    ];

    // Payment mix by amount, percentages summing to 100.
    final byMethod = {for (final m in PaymentMethod.values) m: 0};
    for (final s in inPeriod) {
      byMethod[s.method] = byMethod[s.method]! + s.total;
    }
    final shares = _percentages(byMethod);

    // Top products by amount.
    final units = {for (final p in products.list()) p.id: p.unit};
    final agg = <String, (String, int, int, String)>{}; // key -> (name, qtyMilli, amount, unit)
    for (final s in inPeriod) {
      for (final l in s.lines) {
        final key = l.productId ?? l.name;
        final prev = agg[key] ?? (l.name, 0, 0, units[l.productId] ?? '');
        agg[key] = (prev.$1, prev.$2 + l.qtyMilli, prev.$3 + l.total, prev.$4);
      }
    }
    final top = agg.values.toList()..sort((a, b) => b.$3.compareTo(a.$3));

    final yesterday = _sum(between(today.subtract(const Duration(days: 1)), today), (s) => s.total);
    final todayTotal = _sum(between(today, tomorrow), (s) => s.total);

    return ReportSnapshot(
      summary: summary,
      last7Days: days,
      paymentShares: [for (final m in PaymentMethod.values) PaymentShare(m, shares[m]!)],
      topProducts: [
        for (final t in top.take(4)) TopProduct(t.$1, '${Qty.format(t.$2)} ${t.$4}'.trim(), t.$3),
      ],
      changeVsYesterdayPct: yesterday == 0 ? 0 : _roundDiv((todayTotal - yesterday) * 100, yesterday),
    );
  }

  /// Integer division rounded half away from zero (no doubles).
  static int _roundDiv(int a, int b) => (a * 2 + (a >= 0 ? b : -b)) ~/ (2 * b);

  static int _sum(Iterable<Sale> s, int Function(Sale) f) => s.fold(0, (a, x) => a + f(x));

  /// Largest-remainder rounding so shares add up to exactly 100.
  static Map<PaymentMethod, int> _percentages(Map<PaymentMethod, int> amounts) {
    final total = amounts.values.fold(0, (a, b) => a + b);
    if (total == 0) return {for (final m in amounts.keys) m: 0};
    final base = {for (final e in amounts.entries) e.key: e.value * 100 ~/ total};
    final rem = amounts.entries.toList()
      ..sort((a, b) => (b.value * 100 % total).compareTo(a.value * 100 % total));
    var left = 100 - base.values.fold(0, (a, b) => a + b);
    for (final e in rem) {
      if (left-- <= 0) break;
      base[e.key] = base[e.key]! + 1;
    }
    return base;
  }
}
