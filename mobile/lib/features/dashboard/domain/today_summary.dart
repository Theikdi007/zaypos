import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/async_combine.dart';
import '../../reports/data/report_providers.dart';
import '../../reports/domain/report.dart';
import '../../sales/data/sales_providers.dart';
import '../../sales/domain/sale.dart';

/// Today's totals (kyats), computed from sales (profit from cost snapshots).
class TodaySummary {
  const TodaySummary({required this.sales, required this.count, required this.profit, required this.changePct, required this.pendingSync});
  final int sales;
  final int count;
  final int profit;
  final int changePct;
  final int pendingSync;
}

final todaySummaryProvider = Provider<AsyncValue<TodaySummary>>((ref) => combineAsync(
      ref.watch(reportProvider(ReportPeriod.today)),
      ref.watch(salesProvider),
      (ReportSnapshot r, List<Sale> sales) => TodaySummary(
        sales: r.summary.sales,
        count: r.summary.count,
        profit: r.summary.profit,
        changePct: r.changeVsYesterdayPct,
        pendingSync: sales.where((s) => s.pending).length,
      ),
    ));
