import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

void main() {
  test('every service passes its server unit kind', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final uow = c.read(unitOfWorkProvider) as FakeUnitOfWork;
    final sale = await sell(c, [draft(productId: SeedIds.water)]);
    await c.read(voidSaleServiceProvider).setVoided(sale.id, true);
    await c.read(customerServiceProvider).recordPayment(
        tenantId: 't', customerId: SeedIds.aungKyaw, amount: 100, method: PaymentMethod.cash);
    await c.read(stockServiceProvider).restock(productId: SeedIds.water, qtyMilli: Qty.units(1));
    await c.read(stockServiceProvider).adjust(productId: SeedIds.water, deltaMilli: -1000);
    expect(uow.kinds, [UnitKind.checkout, UnitKind.voidSale, UnitKind.payDebt, UnitKind.restock, UnitKind.stockAdjust]);
    expect(c.read(fakeDatabaseProvider), isA<FakeDatabase>());
  });

  test('UnitKind names are the server unit kinds', () {
    expect(UnitKind.values.map((k) => k.name), [
      'checkout', 'voidSale', 'payDebt', 'upsertProduct', 'upsertCustomer', 'setFeatures', 'stockAdjust', 'restock',
    ]);
  });
}
