import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/report.dart';

abstract interface class ReportRepository {
  PeriodSummary summary(ReportPeriod period);
  List<DaySales> last7Days();
  List<PaymentShare> paymentShares();
  List<TopProduct> topProducts();

  /// Change vs yesterday in percent (dashboard "မနေ့က").
  int changeVsYesterday();
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final reportRepositoryProvider = Provider<ReportRepository>(
  (_) => throw UnimplementedError('reportRepositoryProvider must be overridden'),
);
