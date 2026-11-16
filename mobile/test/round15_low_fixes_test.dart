// Round-15 Low fixes: BUG-57 open cart kept in Drift, BUG-58 phones locked to
// portrait, BUG-60 launcher name, BUG-59 bottom nav at the largest font and
// display size, BUG-54 Burmese date picker, BUG-47 no "Viber သတိပေး" at 0.
// (BUG-51 / BUG-56 back handling: android_back_test.dart.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/widgets/app_bottom_nav.dart';
import 'package:zaypos_app/core/widgets/date_picker.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/features/pos/data/cart_store.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

void main() {
  setUpAll(loadAppFonts);

  group('BUG-57 open cart survives the app being killed', () {
    test('encode / decode keeps every field; broken or unknown data is dropped', () {
      const cart = Cart([
        CartLine(key: 'serial:s1', productId: 'p1', serialId: 's1', name: 'Phone · 3515', price: 450000, cost: 400000, qtyMilli: 1000),
        CartLine(key: 'q1', name: 'အမြန်ရောင်း', price: 500, qtyMilli: 2500),
      ]);
      final back = decodeCart(encodeCart('t1', cart))!;
      expect(back.tenantId, 't1');
      expect(encodeCart('t1', back.cart), encodeCart('t1', cart));
      for (final bad in [null, '', '{', '{"v":2,"tenantId":"t","lines":[]}', '{"v":1,"tenantId":"t","lines":[{"key":1}]}']) {
        expect(decodeCart(bad), isNull, reason: '$bad');
      }
    });

    test('Drift: items in the cart → process killed → app restarted: the cart is back; checkout clears it', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final (c1, shop) = await driftContainer(db);
      final products = await settled(c1, productsProvider);
      final p = products.firstWhere((x) => x.price > 0).product;
      c1.read(cartProvider.notifier)
        ..addProduct(p)
        ..addProduct(p)
        ..addQuick(700, 'ရေခဲ');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = encodeCart(shop.tenantId, c1.read(cartProvider));
      c1.dispose(); // the process is gone: only the database is left

      final saved = await loadOpenCart(db);
      expect(saved, isNotNull);
      final (c2, _) = await driftContainer(db, store: shop.store, overrides: [initialCartProvider.overrideWithValue(CartRestore(saved))]);
      addTearDown(c2.dispose);
      expect(encodeCart(shop.tenantId, c2.read(cartProvider)), before);
      expect(c2.read(cartProvider).lines.map((l) => (l.name, l.qtyMilli)), [(p.name, 2000), ('ရေခဲ', 1000)]);

      c2.read(cartProvider.notifier).clear(); // what a finished checkout does
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await loadOpenCart(db))!.cart.isEmpty, isTrue);
    });

    test('a saved cart of another shop is never restored, and the restore is used only once', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final (c, _) = await driftContainer(db, overrides: [
        initialCartProvider.overrideWithValue(
            CartRestore((tenantId: 'another-shop', cart: const Cart([CartLine(key: 'q', name: 'x', price: 1, qtyMilli: 1000)])))),
      ]);
      addTearDown(c.dispose);
      expect(c.read(cartProvider).isEmpty, isTrue);

      final restore = CartRestore((tenantId: c.read(tenantIdProvider), cart: const Cart([CartLine(key: 'q', name: 'x', price: 1, qtyMilli: 1000)])));
      expect(restore.take(), isNotNull);
      expect(restore.take(), isNull, reason: 'a later rebuild (e.g. sign-out → sign-in) starts empty');
    });
  });

  group('BUG-58 portrait', () {
    testWidgets('a phone is locked to portrait; a tablet is not', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await lockPhonesToPortrait(logicalSize: const Size(390, 844));
      await lockPhonesToPortrait(logicalSize: const Size(320, 693)); // largest display size
      expect(calls.where((c) => c.method == 'SystemChrome.setPreferredOrientations').map((c) => c.arguments),
          [['DeviceOrientation.portraitUp'], ['DeviceOrientation.portraitUp']]);
      calls.clear();
      await lockPhonesToPortrait(logicalSize: const Size(800, 1280));
      expect(calls, isEmpty);
    });

    test('iPhone Info.plist allows portrait only (iPad keeps every orientation)', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final phone = RegExp(r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>', dotAll: true)
          .firstMatch(plist)!
          .group(1)!;
      expect(RegExp('<string>(.*?)</string>').allMatches(phone).map((m) => m.group(1)), ['UIInterfaceOrientationPortrait']);
      expect(plist, contains('UISupportedInterfaceOrientations~ipad'));
    });
  });

  test('BUG-60 the launcher shows "ZayPOS" on Android and iOS', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), contains('android:label="ZayPOS"'));
    expect(RegExp(r'<key>CFBundleDisplayName</key>\s*<string>ZayPOS</string>').hasMatch(File('ios/Runner/Info.plist').readAsStringSync()),
        isTrue);
  });

  group('BUG-59 bottom navigation at the largest font (2.0) and display size (320 dp)', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('text scale $scale: no overflow, five labels on one line each, inside their own button', (tester) async {
        tester.view.physicalSize = const Size(320, 693);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(size: const Size(320, 693), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'e.g. "BOTTOM OVERFLOWED BY 29 PIXELS"');
        final navBox = tester.getRect(find.byType(AppBottomNav));
        final buttons = find.descendant(of: find.byType(AppBottomNav), matching: find.byType(InkWell));
        expect(buttons, findsNWidgets(5));
        for (var i = 0; i < 5; i++) {
          final label = AppBottomNav.items[i].label;
          final text = tester.getRect(find.text(label));
          final button = tester.getRect(buttons.at(i));
          expect(text.left >= button.left - 0.5 && text.right <= button.right + 0.5, isTrue, reason: '$label stays in its button');
          expect(text.bottom <= navBox.bottom, isTrue, reason: '$label is not cut off');
          final para = tester.renderObject<RenderParagraph>(find.text(label));
          expect(para.didExceedMaxLines, isFalse, reason: '$label on one line');
        }
        if (scale == 1.0) expect(navBox.height, 76, reason: 'unchanged at the normal size');
      });
    }
  });

  group('BUG-54 date picker in Burmese', () {
    testWidgets('no English text in the expiry picker (title, months, digits, buttons)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: appLocale,
        supportedLocales: const [appLocale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showExpiryDatePicker(context,
                initialDate: DateTime(2026, 11, 16), firstDate: DateTime(2025), lastDate: DateTime(2036)),
            child: const Text('ဖွင့်'),
          ),
        ),
      ));
      await tester.tap(find.text('ဖွင့်'));
      await tester.pumpAndSettle();
      final texts = [
        for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Dialog), matching: find.byType(Text))))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ];
      expect(texts.where((s) => s.contains(RegExp('[A-Za-z]{2,}'))), isEmpty, reason: '$texts');
      expect(find.text(datePickerConfirmText), findsOneWidget);
      expect(find.text(datePickerCancelText), findsOneWidget);
      expect(find.text('၂၈'), findsOneWidget, reason: 'Myanmar digits');
    });

    test('every date picker in the app goes through showExpiryDatePicker', () {
      final direct = [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && !f.path.endsWith('date_picker.dart') && f.readAsStringSync().contains('showDatePicker('))
            f.path,
      ];
      expect(direct, isEmpty);
    });
  });

  group('BUG-47 "Viber သတိပေး" only for a balance above 0', () {
    test('rule', () {
      expect([2000, 1, 0, -500].map(showDebtReminder), [true, true, false, false]);
    });

    for (final (balance, shown) in [(2000, true), (0, false), (-500, false)]) {
      testWidgets('balance $balance → button ${shown ? 'shown' : 'hidden'}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = ProviderContainer(
            overrides: [...fakeRepositoryOverrides, initialLimitsProvider.overrideWithValue(bundledLimits())]);
        addTearDown(c.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
        await tester.pumpAndSettle();
        final t = DateTime.utc(2026, 11, 1);
        final cust = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'BUG47', phone: '09 790 011 001', createdAt: t, updatedAt: t);
        await c.read(customerServiceProvider).create(cust, openingBalance: balance);
        c.read(appRouterProvider).go(Routes.customer(cust.id));
        await tester.pumpAndSettle();
        expect(find.text('ငွေပြန်ဆပ်မယ်'), findsOneWidget, reason: 'precondition: the debtor screen');
        expect(find.text(debtRemindLabel), shown ? findsOneWidget : findsNothing);
      });
    }
  });
}
