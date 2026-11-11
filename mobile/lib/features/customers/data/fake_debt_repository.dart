import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../../sales/domain/sale.dart';
import '../domain/debt_entry.dart';
import 'debt_repository.dart';

class FakeDebtRepository implements DebtRepository {
  FakeDebtRepository({required this.tenantId}) {
    DebtEntry e(String customerId, DebtEntryType type, int amount, DateTime at,
            {String? saleId, int? saleNo, PaymentMethod? method, String? note}) =>
        DebtEntry(
          id: newId(),
          tenantId: tenantId,
          customerId: customerId,
          type: type,
          amount: amount,
          saleId: saleId,
          saleNo: saleNo,
          method: method,
          note: note,
          createdAt: at,
          updatedAt: at,
        );
    const opening = 'ယခင်အကြွေး';
    _entries.addAll([
      // ဦးအောင်ကျော် — design history (balance 52,000)
      e(SeedIds.aungKyaw, DebtEntryType.creditSale, 24000, todayAt(14, 58), saleId: SeedIds.sale1030, saleNo: 1030),
      e(SeedIds.aungKyaw, DebtEntryType.creditSale, 18500, daysAgoAt(4, 10, 12), saleNo: 987),
      e(SeedIds.aungKyaw, DebtEntryType.payment, 30000, daysAgoAt(13, 17, 40), method: PaymentMethod.cash),
      e(SeedIds.aungKyaw, DebtEntryType.creditSale, 39500, daysAgoAt(17, 9, 5), saleNo: 911),
      // Opening balances carried over from the paper book
      e(SeedIds.thanHtun, DebtEntryType.adjustment, 96000, daysAgoAt(35, 10, 0), note: opening),
      e(SeedIds.khinMa, DebtEntryType.adjustment, 78000, daysAgoAt(5, 10, 0), note: opening),
      e(SeedIds.zawMin, DebtEntryType.adjustment, 45500, daysAgoAt(32, 10, 0), note: opening),
      e(SeedIds.niNi, DebtEntryType.adjustment, 31000, daysAgoAt(9, 10, 0), note: opening),
      e(SeedIds.myatNoe, DebtEntryType.adjustment, 12000, daysAgoAt(1, 10, 0), note: opening),
      e(SeedIds.htet, DebtEntryType.payment, 15000, daysAgoAt(14, 11, 0), method: PaymentMethod.cash),
      e(SeedIds.htet, DebtEntryType.adjustment, 15000, daysAgoAt(14, 10, 0), note: opening),
    ]);
  }

  final String tenantId;
  final _entries = <DebtEntry>[];

  @override
  List<DebtEntry> list() {
    final live = _entries.where((e) => e.deletedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(live);
  }

  @override
  void add(DebtEntry entry) => _entries.add(entry);
}
