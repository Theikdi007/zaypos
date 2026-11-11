import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/report.dart';

/// Read-only reporting queries over sales.
abstract interface class ReportRepository {
  ReportSnapshot report(ReportPeriod period, {DateTime? now});
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final reportRepositoryProvider = Provider<ReportRepository>(
  (_) => throw UnimplementedError('reportRepositoryProvider must be overridden'),
);
