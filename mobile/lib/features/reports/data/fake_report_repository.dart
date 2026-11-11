import '../../sales/domain/sale.dart';
import '../domain/report.dart';
import 'report_repository.dart';

/// Design sample figures (kyats).
class FakeReportRepository implements ReportRepository {
  @override
  PeriodSummary summary(ReportPeriod period) => switch (period) {
        ReportPeriod.today => const PeriodSummary(range: 'ယနေ့', sales: 245800, profit: 41200, count: 32),
        ReportPeriod.week => const PeriodSummary(range: '၇ ရက်', sales: 1651100, profit: 277400, count: 214),
        ReportPeriod.month => const PeriodSummary(range: 'နိုဝင်ဘာ ၁–၁၀', sales: 2412600, profit: 405300, count: 318),
      };

  @override
  List<DaySales> last7Days() => const [
        DaySales('ဗုဒ္ဓ', 198400),
        DaySales('ကြာ', 221000),
        DaySales('သော', 176500),
        DaySales('စနေ', 240300),
        DaySales('တနင်္ဂ', 263900),
        DaySales('တနင်္လာ', 305200),
        DaySales('ယနေ့', 245800),
      ];

  @override
  List<PaymentShare> paymentShares() => const [
        PaymentShare(PaymentMethod.cash, 58),
        PaymentShare(PaymentMethod.kbz, 22),
        PaymentShare(PaymentMethod.wave, 9),
        PaymentShare(PaymentMethod.debt, 11),
      ];

  @override
  List<TopProduct> topProducts() => const [
        TopProduct('ဆန် ပေါ်ဆန်း (၁ ပြည်)', '38 ပြည်', 281200),
        TopProduct('စားသုံးဆီ 1L', '21 ဗူး', 130200),
        TopProduct('ကြက်ဥ (၁၀ လုံး)', '27 ကတ်', 121500),
        TopProduct('ရေသန့် 1L', '96 ဘူး', 57600),
      ];

  @override
  int changeVsYesterday() => 12;
}
