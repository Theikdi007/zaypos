import 'dart:async';

import '../../../core/db/app_database.dart';
import '../../sales/data/drift_sales_repository.dart';
import '../domain/report.dart';
import '../domain/report_builder.dart';
import 'report_repository.dart';

/// Report over the local database; re-computed when sales or products change.
class DriftReportRepository implements ReportRepository {
  DriftReportRepository(this.db, this.sales);
  final AppDatabase db;
  final DriftSalesRepository sales;

  @override
  Stream<ReportSnapshot> watchReport(ReportPeriod period) => db
          .customSelect('SELECT 1', readsFrom: {db.sales, db.saleLines, db.products})
          .watch()
          .asyncMap((_) async {
        final all = await sales.loadSales(where: (s) => s.voidedAt.isNull());
        final units = {for (final p in await db.select(db.products).get()) p.id: p.unit};
        return ReportBuilder.build(all, units, period);
      });
}
