import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reports/data/report_repository.dart';
import '../../reports/domain/report.dart';
import '../../sales/data/sales_providers.dart';

/// Today's totals (kyats): report baseline + sales recorded this session.
class TodaySummary {
  const TodaySummary({required this.sales, required this.count, required this.profit, required this.changePct, required this.pendingSync});
  final int sales;
  final int count;
  final int profit;
  final int changePct;
  final int pendingSync;
}

final todaySummaryProvider = Provider<TodaySummary>((ref) {
  final report = ref.watch(reportRepositoryProvider);
  final sales = ref.watch(salesProvider);
  final sessionIds = ref.read(salesProvider.notifier).sessionSaleIds;
  final base = report.summary(ReportPeriod.today);
  final fresh = sales.where((s) => sessionIds.contains(s.id) && !s.voided);
  return TodaySummary(
    sales: base.sales + fresh.fold(0, (a, s) => a + s.total),
    count: base.count + fresh.length,
    profit: base.profit,
    changePct: report.changeVsYesterday(),
    pendingSync: sales.where((s) => s.pending).length,
  );
});
