import '../../../app/fake_database.dart';
import '../domain/report.dart';
import '../domain/report_builder.dart';
import 'report_repository.dart';

/// Computes reports from the (fake) sales store.
class FakeReportRepository implements ReportRepository {
  FakeReportRepository(this.db);

  final FakeDatabase db;

  @override
  Stream<ReportSnapshot> watchReport(ReportPeriod period) =>
      db.watch({FakeTable.sales, FakeTable.products}, () => report(period));

  /// Synchronous query (also used directly by tests with a fixed [now]).
  ReportSnapshot report(ReportPeriod period, {DateTime? now}) =>
      ReportBuilder.build(db.sales, {for (final p in db.products) p.id: p.unit}, period, now: now);
}
