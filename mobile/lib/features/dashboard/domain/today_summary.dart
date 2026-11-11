import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reports/data/report_providers.dart';
import '../../reports/domain/report.dart';
import '../../sales/data/sales_providers.dart';

/// Today's totals (kyats), computed from sales (profit from cost snapshots).
class TodaySummary {
  const TodaySummary({required this.sales, required this.count, required this.profit, required this.changePct, required this.pendingSync});
  final int sales;
  final int count;
  final int profit;
  final int changePct;
  final int pendingSync;
}

final todaySummaryProvider = Provider<TodaySummary>((ref) {
  final r = ref.watch(reportProvider(ReportPeriod.today));
  return TodaySummary(
    sales: r.summary.sales,
    count: r.summary.count,
    profit: r.summary.profit,
    changePct: r.changeVsYesterdayPct,
    pendingSync: ref.watch(salesProvider).where((s) => s.pending).length,
  );
});
