// QA round 1 — POS / SALE / DEBT / PROD screen behaviour (widget tests on the
// app's screens; fake repositories with the design's sample data, no network).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/data/unit_of_work.dart';
import 'package:zaypos_app/core/widgets/numeric_keypad.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_repository.dart';
import 'package:zaypos_app/features/customers/data/debt_repository.dart';
import 'package:zaypos_app/features/devices/data/device_repository.dart';
import 'package:zaypos_app/features/inventory/data/stock_repository.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/data/sales_repository.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/widgets/money_text.dart';
import 'package:zaypos_app/features/customers/domain/debt_entry.dart';
import 'package:zaypos_app/features/dashboard/domain/today_summary.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

/// Checkout that takes [delay] before committing (a slow phone / busy disk).
class SlowCheckoutService extends CheckoutService {
  SlowCheckoutService(Ref ref, this.delay)
      : super(
          uow: ref.watch(unitOfWorkProvider),
          tenantId: ref.watch(tenantIdProvider),
          sales: ref.watch(salesRepositoryProvider),
          stock: ref.watch(stockRepositoryProvider),
          debt: ref.watch(debtRepositoryProvider),
          customers: ref.watch(customerRepositoryProvider),
          devices: ref.watch(deviceRepositoryProvider),
          products: ref.watch(productRepositoryProvider),
        );
  final Duration delay;

  @override
  Future<Sale> checkout(CheckoutRequest r) async {
    await Future<void>.delayed(delay);
    return super.checkout(r);
  }
}

/// Debt repayment that takes [delay] before committing.
class SlowCustomerService extends CustomerService {
  SlowCustomerService(Ref ref, this.delay)
      : super(uow: ref.watch(unitOfWorkProvider), customers: ref.watch(customerRepositoryProvider), debt: ref.watch(debtRepositoryProvider));
  final Duration delay;

  @override
  Future<DebtEntry> recordPayment({required String tenantId, required String customerId, required int amount, required PaymentMethod method}) async {
    await Future<void>.delayed(delay);
    return super.recordPayment(tenantId: tenantId, customerId: customerId, amount: amount, method: method);
  }
}

const _slow = Duration(milliseconds: 300);

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester, {List<Override> extra = const [], double height = 844}) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [...fakeRepositoryOverrides, ...extra]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  FakeDatabase db(ProviderContainer c) => c.read(fakeDatabaseProvider);

  /// The one sale created since [before] (ids).
  Sale newSale(ProviderContainer c, Set<String> before) => db(c).sales.where((s) => !before.contains(s.id)).single;
  Set<String> saleIds(ProviderContainer c) => {for (final s in db(c).sales) s.id};

  Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
    await tester.tap(last ? find.text(text).last : find.text(text).first);
    await tester.pumpAndSettle();
  }

  Future<void> openPosProducts(WidgetTester tester, ProviderContainer c) async {
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    await tapText(tester, 'ပစ္စည်းများ');
  }

  // ---------------------------------------------------------------- TC-POS-01
  testWidgets('TC-POS-01 product tapped 2× → cash, received 10,000 → change 8,800, receipt, today total updates',
      (tester) async {
    final c = await boot(tester);
    final today = c.listen(todaySummaryProvider, (_, _) {});
    addTearDown(today.close);
    final todayBefore = today.read().requireValue.sales;
    final expectedNo = db(c).devices.first.nextReceiptNo;

    await openPosProducts(tester, c);
    await tapText(tester, 'ရေသန့် 1L'); // 600 Ks
    await tapText(tester, 'ရေသန့် 1L');
    expect(c.read(cartProvider).total, 1200);
    await tapText(tester, 'ငွေရှင်းမယ်');
    await tester.enterText(find.byType(TextFormField), '10000');
    await tester.pumpAndSettle();
    expect(find.text('8,800 Ks'), findsOneWidget, reason: 'change = 10,000 − 1,200');

    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');

    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
    expect(find.textContaining(expectedNo), findsWidgets, reason: 'receipt shows the next number $expectedNo');
    final sale = db(c).sales.firstWhere((s) => s.no == expectedNo);
    expect((sale.method, sale.total, sale.payments.single.received), (PaymentMethod.cash, 1200, 10000));
    await tester.pumpAndSettle();
    expect(today.read().requireValue.sales, todayBefore + 1200);
    // And on the Dashboard itself.
    c.read(appRouterProvider).go(Routes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is MoneyText && w.amount == todayBefore + 1200), findsWidgets);
  });

  // ---------------------------------------------------------------- TC-POS-04
  testWidgets('TC-POS-04 Quick Sale 2,500 "ဆပ်ပြာ" + Quick Sale 1,000 → two lines without product, 3,500, no stock movement',
      (tester) async {
    final c = await boot(tester);
    final movementsBefore = db(c).stock.length;
    final ids = saleIds(c);
    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();

    Future<void> key(String k) async {
      await tester.tap(find.descendant(of: find.byType(NumericKeypad), matching: find.text(k)));
      await tester.pump();
    }
    for (final k in ['2', '5', '00']) {
      await key(k);
    }
    await tester.enterText(find.byType(EditableText).first, 'ဆပ်ပြာ');
    await tapText(tester, '+ ခြင်းထဲထည့်မယ်');
    for (final k in ['1', '0', '00']) {
      await key(k);
    }
    await tapText(tester, '+ ခြင်းထဲထည့်မယ်');
    expect(c.read(cartProvider).total, 3500);

    await tapText(tester, 'ငွေရှင်းမယ်');
    expect(find.text('3,500 Ks'), findsWidgets);
    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');

    final sale = newSale(c, ids);
    expect(sale.total, 3500);
    expect(sale.lines.map((l) => (l.productId, l.name, l.price)), [(null, 'ဆပ်ပြာ', 2500), (null, quickSaleName, 1000)]);
    expect(db(c).stock.length, movementsBefore, reason: 'Quick Sale lines move no stock');
  });

  // ---------------------------------------------------------------- TC-POS-07
  testWidgets('TC-POS-07 double-tap Confirm (slow commit, taps 60 ms apart) → one sale only', (tester) async {
    final c = await boot(tester, extra: [
      checkoutServiceProvider.overrideWith((ref) => SlowCheckoutService(ref, _slow)),
    ]);
    final before = db(c).sales.length;
    await openPosProducts(tester, c);
    await tapText(tester, 'ရေသန့် 1L');
    await tapText(tester, 'ငွေရှင်းမယ်');

    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(db(c).sales.length, before + 1);
  });

  // ---------------------------------------------------------------- TC-POS-08 + TC-SALE-04
  testWidgets('TC-POS-08 / TC-SALE-04 KBZPay sale saved as kbz; history filters match; voided struck through',
      (tester) async {
    final c = await boot(tester, height: 3000); // tall: every history row is built
    final ids = saleIds(c);
    await openPosProducts(tester, c);
    await tapText(tester, 'ရေသန့် 1L');
    await tapText(tester, 'ငွေရှင်းမယ်');
    await tapText(tester, 'KBZPay');
    await tapText(tester, 'အတည်ပြုပြီး ပြေစာထုတ်မယ်');
    final kbzSale = newSale(c, ids);
    expect((kbzSale.method, kbzSale.payments.single.method), (PaymentMethod.kbz, PaymentMethod.kbz));

    c.read(appRouterProvider).go(Routes.sales);
    await tester.pumpAndSettle();
    final today = db(c).sales.where((s) => DateUtils.isSameDay(s.createdAt.toLocal(), DateTime.now())).toList();
    for (final (label, method) in [
      ('ငွေသား', PaymentMethod.cash),
      ('KBZPay', PaymentMethod.kbz),
      ('WavePay', PaymentMethod.wave),
      ('အကြွေး', PaymentMethod.debt),
      ('အားလုံး', null),
    ]) {
      await tester.ensureVisible(find.text(label).first); // the chip row scrolls sideways
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      final expected = today.where((s) => method == null || s.method == method).toList();
      for (final s in today) {
        expect(find.textContaining('#${s.no}'), expected.contains(s) ? findsOneWidget : findsNothing,
            reason: 'filter $label, sale ${s.no} (${s.method.name})');
      }
    }

    // Void today's KBZ sale: struck through + "ပယ်ဖျက်ပြီး".
    c.read(appRouterProvider).push(Routes.sale(kbzSale.id));
    await tester.pumpAndSettle();
    await tapText(tester, 'ပယ်ဖျက်မယ်');
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go(Routes.sales);
    await tester.pumpAndSettle();
    expect(find.text('ပယ်ဖျက်ပြီး'), findsWidgets);
    final struck = tester.widgetList<MoneyText>(find.byType(MoneyText)).where((m) => m.strike).length;
    expect(struck, greaterThanOrEqualTo(1));
  });

  // ---------------------------------------------------------------- TC-PROD-02
  testWidgets('TC-PROD-02 add product: cost 450, price 600, unit ဗူး → margin +150 Ks (33%), saved', (tester) async {
    final c = await boot(tester);
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('productName')), 'QA ဖျော်ရည်');
    await tester.enterText(find.byKey(const ValueKey('price')), '600');
    final sampleCost = '${c.read(shopTemplateProvider).sampleCost}';
    await tester.enterText(find.byWidgetPredicate((w) => w is EditableText && w.controller.text == sampleCost), '450');
    await tester.pumpAndSettle();
    expect(find.text('+150 Ks (33%)'), findsOneWidget);

    // Unit dropdown → ဗူး.
    await tester.tap(find.text(c.read(shopTemplateProvider).units.first).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'ဗူး', last: true);
    await tapText(tester, 'သိမ်းမယ်', last: true);
    final p = db(c).products.firstWhere((p) => p.name == 'QA ဖျော်ရည်');
    expect((p.cost, p.price, p.unit), (450, 600, 'ဗူး'));
  });

  // ---------------------------------------------------------------- TC-PROD-12
  testWidgets('TC-PROD-12 hardware: stock 2.5 → 2500 milli, shown as 2.5', (tester) async {
    final c = await boot(tester);
    c.read(shopTemplateProvider.notifier).select('hardware');
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('productName')), 'QA သံချောင်း');
    await tester.enterText(find.byKey(const ValueKey('price')), '600');
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('stockQty')), '2.5');
    await tapText(tester, 'သိမ်းမယ်', last: true);

    final p = db(c).products.firstWhere((p) => p.name == 'QA သံချောင်း');
    final m = db(c).stock.where((m) => m.productId == p.id).single;
    expect((m.type, m.qtyMilli), (StockMovementType.restock, 2500));
    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'QA သံချောင်း');
    await tester.pumpAndSettle();
    expect(find.textContaining('2.5'), findsWidgets, reason: 'stock shown as 2.5');
  });

  // ---------------------------------------------------------------- TC-POS-NEW-1
  testWidgets('TC-POS-NEW-1 hardware (decimalQty on): the cashier can sell 2.5 of a product', (tester) async {
    final c = await boot(tester);
    c.read(shopTemplateProvider.notifier).select('hardware');
    expect(c.read(tenantFeaturesProvider).decimalQty, isTrue);
    final water = db(c).products.firstWhere((p) => p.id == SeedIds.water);
    c.read(cartProvider.notifier).addProduct(water);
    c.read(appRouterProvider).go(Routes.checkout);
    await tester.pumpAndSettle();

    // Expected: some way to set the line quantity to 2.5 — a quantity field or a keypad with a decimal point
    // opened from the line's quantity. Only whole-unit −/+ steppers exist.
    final before = find.byType(EditableText).evaluate().length;
    await tester.tap(find.text('1').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    final hasQtyEditor = find.byType(EditableText).evaluate().length > before || find.text('.').evaluate().isNotEmpty;
    expect(hasQtyEditor, isTrue, reason: 'no way to enter a decimal quantity (2.5 ပေ) in POS or checkout');
  });

  // ---------------------------------------------------------------- TC-DEBT-NEW-2
  testWidgets('TC-DEBT-NEW-2 double-tap "… Ks လက်ခံမယ်" (taps 100 ms apart, 150 ms write) records ONE payment',
      (tester) async {
    final c = await boot(tester, extra: [
      customerServiceProvider.overrideWith((ref) => SlowCustomerService(ref, const Duration(milliseconds: 150))),
    ]);
    final payments = db(c).debt.where((e) => e.type == DebtEntryType.payment).length;
    c.read(appRouterProvider).go(Routes.customer(SeedIds.aungKyaw));
    await tester.pumpAndSettle();
    await tapText(tester, 'ငွေပြန်ဆပ်မယ်');
    await tapText(tester, '20,000');

    await tester.tap(find.text('20,000 Ks လက်ခံမယ်'));
    await tester.pump(const Duration(milliseconds: 100)); // a quick double tap; the write takes 150 ms
    await tester.tap(find.text('20,000 Ks လက်ခံမယ်'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(db(c).debt.where((e) => e.type == DebtEntryType.payment).length, payments + 1);
    expect(find.text('32,000 Ks'), findsOneWidget, reason: '52,000 − 20,000 once');
  });

  // ---------------------------------------------------------------- TC-DEBT-NEW-1
  testWidgets('TC-DEBT-NEW-1 credit sale over the customer limit: checkout warns (as the add-customer helper promises)',
      (tester) async {
    final c = await boot(tester);
    // ဦးသန်းထွန်း owes 96,000 (seed). Give him a 100,000 limit, then sell 24,000 on credit.
    final i = db(c).customers.indexWhere((x) => x.id == SeedIds.thanHtun);
    db(c).customers[i] = db(c).customers[i].copyWith(creditLimit: () => 100000);
    db(c).touch({FakeTable.customers});
    final water = db(c).products.firstWhere((p) => p.id == SeedIds.water);
    for (var k = 0; k < 40; k++) {
      c.read(cartProvider.notifier).addProduct(water); // 40 × 600 = 24,000
    }
    c.read(appRouterProvider).go(Routes.checkout);
    await tester.pumpAndSettle();
    await tapText(tester, 'အကြွေး');
    await tapText(tester, 'ရွေးရန်');
    await tapText(tester, 'ဦးသန်းထွန်း');
    expect(find.text('ယခင်အကြွေး 96,000 Ks'), findsOneWidget, reason: 'customer picked');
    expect(find.text('24,000 Ks'), findsWidgets, reason: 'cart total');

    expect(find.textContaining('ကန့်သတ်'), findsWidgets,
        reason: 'add_customer: "ဒီထက်ကျော်ရင် ရောင်းတဲ့အချိန် သတိပေးပါမယ်" — 96,000 + 24,000 > 100,000');
  });
}
