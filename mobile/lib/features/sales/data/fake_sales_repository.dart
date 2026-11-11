import 'dart:math';

import '../../../app/fake_database.dart';
import '../../../app/fake_seed.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../../devices/domain/device.dart';
import '../domain/sale.dart';
import 'sales_repository.dart';

/// Sample sales: the design's six "today" sales (A-1027 … A-1032) plus a
/// deterministic 29-day history so reports/profit are real queries.
List<Sale> seedSales(String tenantId) {
  final s = _SalesSeeder(tenantId);
  return [...s.today(), ...s.history(lastSeq: 1026)];
}

class _SalesSeeder {
  _SalesSeeder(this.tenantId);
  final String tenantId;

  /// (productId, name, qty units, price, cost)
  Sale _seed(
    String id,
    int seq,
    PaymentMethod m,
    DateTime at,
    List<(String?, String, int, int, int)> lines, {
    bool synced = true,
    bool voided = false,
    String? customerId,
    String? customerName,
  }) {
    final sl = [
      for (final (pid, name, qty, price, cost) in lines)
        SaleLine(
          id: newId(),
          tenantId: tenantId,
          saleId: id,
          productId: pid,
          name: name,
          qtyMilli: Qty.units(qty),
          price: price,
          costSnapshot: cost,
          createdAt: at,
          updatedAt: at,
        ),
    ];
    final total = sl.fold(0, (a, l) => a + l.total);
    return Sale(
      id: id,
      tenantId: tenantId,
      no: formatReceiptNo('A', seq),
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

  (String?, String, int, int, int) _p(String id, int qty) {
    final p = SeedCatalog.byId(id);
    return (p.id, p.name, qty, p.price, p.cost);
  }

  (String?, String, int, int, int) _x((String, int, int) item, int qty) =>
      (null, item.$1, qty, item.$3, item.$2);

  List<Sale> today() {
    const salt = SeedCatalog.salt, lighter = SeedCatalog.lighter;
    return [
      _seed(SeedIds.sale1032, 1032, PaymentMethod.cash, todayAt(15, 42), [
        _p(SeedIds.oil, 1),
        _p(SeedIds.eggs, 1),
        _x(salt, 2),
        _x(lighter, 2),
      ], synced: false),
      _seed(SeedIds.sale1031, 1031, PaymentMethod.kbz, todayAt(15, 15), [
        _p(SeedIds.oil, 1),
        _p(SeedIds.water, 1),
      ], synced: false),
      _seed(
        SeedIds.sale1030,
        1030,
        PaymentMethod.debt,
        todayAt(14, 58),
        [
          _p(SeedIds.rice, 2),
          _p(SeedIds.oil, 1),
          _p(SeedIds.water, 2),
          _p(SeedIds.noodles, 1),
          _x(salt, 1),
          _x(lighter, 1),
        ],
        customerId: SeedIds.aungKyaw,
        customerName: 'ဦးအောင်ကျော်',
      ),
      _seed(SeedIds.sale1029, 1029, PaymentMethod.wave, todayAt(14, 31), [
        _x(lighter, 8),
      ]),
      _seed(SeedIds.sale1028, 1028, PaymentMethod.cash, todayAt(13, 47), [
        _p(SeedIds.rice, 1),
        _p(SeedIds.soap, 1),
        _p(SeedIds.eggs, 1),
        _p(SeedIds.water, 1),
        _x(lighter, 1),
      ]),
      _seed(SeedIds.sale1027, 1027, PaymentMethod.cash, todayAt(13, 20), [
        _p(SeedIds.eggs, 1),
      ], voided: true),
    ];
  }

  /// Past 29 days, 18–29 sales/day, cash/KBZPay/WavePay (credit history
  /// lives in the debt ledger seed). Numbered consecutively up to [lastSeq].
  List<Sale> history({required int lastSeq}) {
    final r = Random(42);
    final drafts =
        <(DateTime, PaymentMethod, List<(String?, String, int, int, int)>)>[];
    for (var day = 29; day >= 1; day--) {
      final n = 18 + r.nextInt(12);
      final times = [for (var i = 0; i < n; i++) (7 * 60 + r.nextInt(13 * 60))]
        ..sort();
      for (final minutes in times) {
        final roll = r.nextInt(100);
        final method = roll < 62
            ? PaymentMethod.cash
            : (roll < 87 ? PaymentMethod.kbz : PaymentMethod.wave);
        final picks = <String>{};
        final count = 1 + r.nextInt(4);
        while (picks.length < count) {
          picks.add(SeedCatalog.items[r.nextInt(SeedCatalog.items.length)].id);
        }
        drafts.add((
          daysAgoAt(day, minutes ~/ 60, minutes % 60),
          method,
          [for (final id in picks) _p(id, 1 + r.nextInt(3))],
        ));
      }
    }
    var seq = lastSeq - drafts.length + 1;
    return [
      for (final (at, m, lines) in drafts) _seed(newId(), seq++, m, at, lines),
    ].reversed.toList();
  }
}

class FakeSalesRepository implements SalesRepository {
  FakeSalesRepository(this.db);
  final FakeDatabase db;

  @override
  List<Sale> list() =>
      List.unmodifiable(db.sales.where((s) => s.deletedAt == null));

  @override
  Sale? byId(String id) {
    for (final s in db.sales) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void add(Sale sale) => db.sales.insert(0, sale);

  @override
  void setVoided(String id, bool voided) {
    final i = db.sales.indexWhere((s) => s.id == id);
    if (i < 0) throw StateError('Unknown sale $id');
    final t = nowUtc();
    db.sales[i] = db.sales[i].copyWith(
      voidedAt: () => voided ? t : null,
      updatedAt: t,
    );
  }
}
