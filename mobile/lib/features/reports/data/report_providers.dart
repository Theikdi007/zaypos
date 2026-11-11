import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sales/data/sales_providers.dart';
import '../domain/report.dart';
import 'report_repository.dart';

/// Report for a period; recomputed whenever sales change.
final reportProvider = Provider.family<ReportSnapshot, ReportPeriod>((ref, period) {
  ref.watch(salesProvider);
  return ref.watch(reportRepositoryProvider).report(period);
});
