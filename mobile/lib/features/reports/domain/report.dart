import '../../sales/domain/sale.dart';

enum ReportPeriod {
  today('ဒီနေ့'),
  week('ဒီအပတ်'),
  month('ဒီလ');

  const ReportPeriod(this.label);
  final String label;
}

/// All money in int kyats.
class PeriodSummary {
  const PeriodSummary({
    required this.range,
    required this.sales,
    required this.profit,
    required this.count,
    this.knownCostLines = 0,
    this.unknownCostLines = 0,
  });
  final String range;
  final int sales;

  /// Σ (price − costSnapshot) × qty over non-voided sale lines whose cost is
  /// known; lines with an unknown cost (0) are left out (BUG-53).
  final int profit;
  final int count;

  /// Sold lines that count in [profit].
  final int knownCostLines;

  /// Sold lines left out of [profit] because their cost is unknown.
  final int unknownCostLines;

  /// Lines were sold but not one had a cost: show "အရင်းမသိ", not 0 Ks.
  bool get profitUnknown => knownCostLines == 0 && unknownCostLines > 0;
}

class DaySales {
  const DaySales(this.day, this.amount);
  final String day;
  final int amount;
}

class PaymentShare {
  const PaymentShare(this.method, this.percent);
  final PaymentMethod method;
  final int percent;
}

class TopProduct {
  const TopProduct(this.name, this.qtyLabel, this.amount);
  final String name;
  final String qtyLabel;
  final int amount;
}

/// Everything the Report screen (and dashboard) shows for one period.
class ReportSnapshot {
  const ReportSnapshot({
    required this.summary,
    required this.last7Days,
    required this.paymentShares,
    required this.topProducts,
    required this.changeVsYesterdayPct,
  });

  final PeriodSummary summary;
  final List<DaySales> last7Days;
  final List<PaymentShare> paymentShares;
  final List<TopProduct> topProducts;

  /// Today's sales vs yesterday, whole percent.
  final int changeVsYesterdayPct;
}
