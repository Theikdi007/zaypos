import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/report.dart';
import 'report_repository.dart';

/// Report for a period (live; recomputed whenever sales change).
final reportProvider = StreamProvider.family<ReportSnapshot, ReportPeriod>(
  (ref, period) => ref.watch(reportRepositoryProvider).watchReport(period),
);
