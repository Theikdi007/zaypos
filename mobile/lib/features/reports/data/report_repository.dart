import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/report.dart';

/// Read-only reporting queries over sales; re-emits when sales change.
abstract interface class ReportRepository {
  Stream<ReportSnapshot> watchReport(ReportPeriod period);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final reportRepositoryProvider = Provider<ReportRepository>(
  (_) => throw UnimplementedError('reportRepositoryProvider must be overridden'),
);
