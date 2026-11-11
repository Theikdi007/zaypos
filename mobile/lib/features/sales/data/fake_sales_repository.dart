import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../domain/sale.dart';
import 'sales_repository.dart';

class FakeSalesRepository implements SalesRepository {
  FakeSalesRepository({required this.tenantId}) {
    Sale seed(
      String id,
      int no,
      PaymentMethod m,
      DateTime at,
      List<(String?, String, int, int)> lines, {
      bool synced = true,
      bool voided = false,
      String? customerId,
      String? customerName,
    }) {
      final sl = [
        for (final (pid, name, qty, price) in lines)
          SaleLine(
            id: newId(),
            tenantId: tenantId,
            saleId: id,
            productId: pid,
            name: name,
            qtyMilli: Qty.units(qty),
            price: price,
            createdAt: at,
            updatedAt: at,
          ),
      ];
      final total = sl.fold(0, (a, l) => a + l.total);
      return Sale(
        id: id,
        tenantId: tenantId,
        no: no,
        method: m,
        lines: sl,
        payments: m == PaymentMethod.debt
            ? const []
            : [
                Payment(
                  id: newId(),
                  tenantId: tenantId,
                  saleId: id,
                  method: m,
                  amount: total,
                  createdAt: at,
                  updatedAt: at,
                ),
              ],
        customerId: customerId,
        customerName: customerName,
        voidedAt: voided ? at : null,
        syncedAt: synced ? at : null,
        createdAt: at,
        updatedAt: at,
      );
    }

    const salt = 'ဆား', lighter = 'မီးခြစ်';
    _sales.addAll([
      seed(SeedIds.sale1032, 1032, PaymentMethod.cash, todayAt(15, 42), [
        (SeedIds.oil, 'စားသုံးဆီ 1L', 1, 6200),
        (SeedIds.eggs, 'ကြက်ဥ (၁၀ လုံး)', 1, 4500),
        (null, salt, 2, 500),
        (null, lighter, 2, 400),
      ], synced: false),
      seed(SeedIds.sale1031, 1031, PaymentMethod.kbz, todayAt(15, 15), [
        (SeedIds.oil, 'စားသုံးဆီ 1L', 1, 6200),
        (SeedIds.water, 'ရေသန့် 1L', 1, 600),
      ], synced: false),
      seed(SeedIds.sale1030, 1030, PaymentMethod.debt, todayAt(14, 58), [
        (SeedIds.rice, 'ဆန် ပေါ်ဆန်း (၁ ပြည်)', 2, 7400),
        (SeedIds.oil, 'စားသုံးဆီ 1L', 1, 6200),
        (SeedIds.water, 'ရေသန့် 1L', 2, 600),
        (SeedIds.noodles, 'ခေါက်ဆွဲခြောက်', 1, 900),
        (null, salt, 1, 500),
        (null, lighter, 1, 400),
      ], customerId: SeedIds.aungKyaw, customerName: 'ဦးအောင်ကျော်'),
      seed(SeedIds.sale1029, 1029, PaymentMethod.wave, todayAt(14, 31), [
        (null, lighter, 8, 400),
      ]),
      seed(SeedIds.sale1028, 1028, PaymentMethod.cash, todayAt(13, 47), [
        (SeedIds.rice, 'ဆန် ပေါ်ဆန်း (၁ ပြည်)', 1, 7400),
        (SeedIds.soap, 'ဆပ်ပြာမှုန့် 500g', 1, 2800),
        (SeedIds.eggs, 'ကြက်ဥ (၁၀ လုံး)', 1, 4500),
        (SeedIds.water, 'ရေသန့် 1L', 1, 600),
        (null, lighter, 1, 400),
      ]),
      seed(SeedIds.sale1027, 1027, PaymentMethod.cash, todayAt(13, 20), [
        (SeedIds.eggs, 'ကြက်ဥ (၁၀ လုံး)', 1, 4500),
      ], voided: true),
    ]);
  }

  final String tenantId;
  final _sales = <Sale>[];

  @override
  List<Sale> list() => List.unmodifiable(_sales.where((s) => s.deletedAt == null));

  @override
  Sale? byId(String id) {
    for (final s in _sales) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  int nextNumber() => _sales.fold(0, (a, s) => s.no > a ? s.no : a) + 1;

  @override
  void add(Sale sale) => _sales.insert(0, sale);

  @override
  void setVoided(String id, bool voided) {
    final i = _sales.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final t = nowUtc();
    _sales[i] = _sales[i].copyWith(voidedAt: () => voided ? t : null, updatedAt: t);
  }
}
