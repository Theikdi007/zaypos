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
  const PeriodSummary({required this.range, required this.sales, required this.profit, required this.count});
  final String range;
  final int sales;
  final int profit;
  final int count;
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
