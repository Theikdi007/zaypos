import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/shop_template.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/main.dart';

import 'helpers.dart';

/// Pumps every route at the design size and fails on any layout overflow
/// or exception, using the real bundled fonts.
void main() {
  setUpAll(loadAppFonts);

  Future<(ProviderContainer, GoRouter)> boot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return (container, container.read(appRouterProvider));
  }

  final routes = <String Function()>[
    () => '/login',
    () => '/register',
    () => '/register?step=2',
    () => '/register?step=3',
    () => '/register?step=4',
    () => '/',
    () => '/sales',
    () => '/sales/${SeedIds.sale1030}',
    () => '/sales/${SeedIds.sale1027}',
    () => '/sales/${SeedIds.sale1032}/receipt',
    () => '/reports',
    () => '/pos',
    () => '/products',
    () => '/products/new',
    () => '/customers',
    () => '/customers/new',
    () => '/customers/${SeedIds.aungKyaw}',
    () => '/settings/features',
  ];

  for (final size in const [Size(390, 844), Size(360, 740)]) {
    for (final (i, r) in routes.indexed) {
      testWidgets('renders route #$i at $size', (tester) async {
        final (_, router) = await boot(tester, size: size);
        router.go(r());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: r());
      });
    }
  }

  for (final t in ShopTemplate.all) {
    testWidgets('add product for template ${t.id}', (tester) async {
      final (c, router) = await boot(tester);
      c.read(shopTemplateProvider.notifier).select(t.id);
      router.go('/products/new');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('POS → checkout → receipt flow', (tester) async {
    final (_, router) = await boot(tester);
    router.go('/pos');
    await tester.pumpAndSettle();
    for (final k in ['2', '5', '00']) {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await tester.tap(find.text('+ ခြင်းထဲထည့်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ထည့်ပြီး: 2,500 Ks'), findsOneWidget);
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ရေသန့် 1L'));
    await tester.pumpAndSettle();
    expect(find.text('3,100 Ks'), findsOneWidget);
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အကြွေး'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KBZPay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ငွေသား'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credit checkout adds a creditSale entry to the ledger', (tester) async {
    final (_, router) = await boot(tester);
    router.go('/pos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ရေသန့် 1L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('အကြွေး'));
    await tester.pumpAndSettle();
    // No customer chosen yet: confirm is blocked with a hint.
    expect(find.text('အကြွေးရောင်းရန် ဖောက်သည် ရွေးပါ'), findsOneWidget);
    await tester.tap(find.text('ရွေးရန်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ဦးသန်းထွန်း'));
    await tester.pumpAndSettle();
    expect(find.text('ယခင်အကြွေး 96,000 Ks'), findsOneWidget);
    expect(find.text('အကြွေးရောင်းရန် ဖောက်သည် ရွေးပါ'), findsNothing);
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    router.go('/customers/${SeedIds.thanHtun}');
    await tester.pumpAndSettle();
    expect(find.text('96,600 Ks'), findsOneWidget);
    expect(find.text('အကြွေးဝယ် · #1033'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pay debt sheet records a payment entry', (tester) async {
    final (_, router) = await boot(tester);
    router.go('/customers/${SeedIds.aungKyaw}');
    await tester.pumpAndSettle();
    expect(find.text('52,000 Ks'), findsOneWidget);
    await tester.tap(find.text('ငွေပြန်ဆပ်မယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20,000'));
    await tester.pumpAndSettle();
    expect(find.text('32,000 Ks'), findsOneWidget);
    await tester.tap(find.text('20,000 Ks လက်ခံမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ငွေပြန်ဆပ် · ငွေသား'), findsNWidgets(2)); // sample + new
    expect(find.text('ယခုလေးတင်'), findsOneWidget);
    expect(find.text('32,000 Ks'), findsOneWidget); // new balance
    expect(tester.takeException(), isNull);
  });

  testWidgets('voiding a credit sale reverses it in the ledger (row hidden)', (tester) async {
    final (_, router) = await boot(tester);
    router.go('/sales/${SeedIds.sale1030}');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပယ်ဖျက်မယ်'));
    await tester.pumpAndSettle();
    router.go('/customers/${SeedIds.aungKyaw}');
    await tester.pumpAndSettle();
    expect(find.text('28,000 Ks'), findsOneWidget);
    expect(find.text('void'), findsNothing);
  });

  Future<void> toCheckout(WidgetTester tester, GoRouter router) async {
    router.go('/pos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ပစ္စည်းများ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ရေသန့် 1L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ငွေရှင်းမယ်'));
    await tester.pumpAndSettle();
  }

  testWidgets('debt checkout without a customer cannot be confirmed', (tester) async {
    final (c, router) = await boot(tester);
    await toCheckout(tester, router);
    await tester.tap(find.text('အကြွေး'));
    await tester.pumpAndSettle();
    final before = c.read(salesProvider).length;
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsNothing);
    expect(c.read(salesProvider).length, before);
  });

  testWidgets('cash received below total blocks confirm; enough unblocks', (tester) async {
    final (_, router) = await boot(tester);
    await toCheckout(tester, router); // total 600
    await tester.enterText(find.byType(TextFormField), '500');
    await tester.pumpAndSettle();
    expect(find.text('လက်ခံရရှိငွေ စုစုပေါင်းထက် နည်းနေပါသည်'), findsOneWidget);
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '1000');
    await tester.pumpAndSettle();
    expect(find.text('လက်ခံရရှိငွေ စုစုပေါင်းထက် နည်းနေပါသည်'), findsNothing);
    expect(find.text('400 Ks'), findsOneWidget); // change
    await tester.tap(find.text('အတည်ပြုပြီး ပြေစာထုတ်မယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ရောင်းပြီးပါပြီ'), findsOneWidget);
  });
}
