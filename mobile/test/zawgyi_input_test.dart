// BUG-52: Zawgyi-typed free text is converted to Unicode before it is saved
// (names, product names, notes, addresses, categories, units, sizes / colours,
// batch numbers, quick-sale names, the shop name) and search boxes accept a
// Zawgyi-typed query. The rule itself is tested in myanmar_text_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/customers/presentation/widgets/customer_row.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

// Real Zawgyi (what a Zawgyi keyboard sends) → the Unicode spelling.
const zgName = 'ေမာင္ေမာင္', uName = 'မောင်မောင်';
const zgAddress = 'ရန္ကုန္ၿမိဳ႕', uAddress = 'ရန်ကုန်မြို့';
const zgNote = 'ေနာက္လ ေပးမယ္', uNote = 'နောက်လ ပေးမယ်';
const zgProduct = 'ႏြားႏို႔ ၁ ဗူး', uProduct = 'နွားနို့ ၁ ဗူး';
const zgCategory = 'အခ်ိဳရည္', uCategory = 'အချိုရည်';
const zgUnit = 'ဗူး', uUnit = 'ဗူး'; // identical in both encodings: unchanged
const zgColor = 'အနက္ေရာင္', uColor = 'အနက်ရောင်';
const zgShop = 'ေရႊဝါ ကုန္စုံ', uShop = 'ရွှေဝါ ကုန်စုံ';

Customer _customer(String tenantId, {String name = zgName}) {
  final t = DateTime.utc(2026, 11, 1);
  return Customer(
      id: newId(), tenantId: tenantId, name: name, phone: '09 790 011 152', address: zgAddress, note: zgNote,
      createdAt: t, updatedAt: t);
}

Product _product(String tenantId) {
  final t = DateTime.utc(2026, 11, 1);
  return Product(
      id: newId(), tenantId: tenantId, name: zgProduct, cost: 0, price: 1500, category: zgCategory, unit: zgUnit,
      tint: 0, initial: String.fromCharCode(zgProduct.runes.first), createdAt: t, updatedAt: t);
}

void main() {
  setUpAll(loadAppFonts);

  test('Zawgyi samples really are Zawgyi (guard against a typo in this file)', () {
    for (final (z, u) in [(zgName, uName), (zgAddress, uAddress), (zgNote, uNote), (zgProduct, uProduct),
        (zgCategory, uCategory), (zgColor, uColor), (zgShop, uShop)]) {
      expect(z, isNot(u));
    }
  });

  group('services save Unicode', () {
    test('customer create and edit: name, address, note', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final cust = _customer(c.read(tenantIdProvider));
      await c.read(customerServiceProvider).create(cust);
      final saved = c.read(fakeDatabaseProvider).customers.singleWhere((x) => x.id == cust.id);
      expect((saved.name, saved.address, saved.note, saved.initial), (uName, uAddress, uNote, 'မ'));

      await c.read(customerServiceProvider).update(saved.copyWith(name: 'ေဒၚလွ', updatedAt: DateTime.utc(2026, 11, 2)));
      expect(c.read(fakeDatabaseProvider).customers.singleWhere((x) => x.id == cust.id).name, 'ဒေါ်လှ');
    });

    test('product create: name, category, unit, avatar initial, size / colour, batch number', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final tenant = c.read(tenantIdProvider);
      final p = _product(tenant);
      final t = DateTime.utc(2026, 11, 1);
      await c.read(productServiceProvider).create(p,
          variants: [ProductVariant(id: newId(), tenantId: tenant, productId: p.id, size: 'M', color: zgColor, createdAt: t, updatedAt: t)],
          batches: [ProductBatch(id: newId(), tenantId: tenant, productId: p.id, batchNo: 'ဘ္၁', qtyMilli: 0, createdAt: t, updatedAt: t)]);
      final db = c.read(fakeDatabaseProvider);
      final saved = db.products.singleWhere((x) => x.id == p.id);
      expect((saved.name, saved.category, saved.unit), (uProduct, uCategory, uUnit));
      expect(saved.initial, 'န', reason: 'the avatar shows the Unicode first letter, not a Zawgyi-only glyph');
      expect(db.variants.singleWhere((v) => v.productId == p.id).color, uColor);
      expect(db.batches.singleWhere((b) => b.productId == p.id).batchNo, isNot('ဘ္၁'));
    });

    test('edit product and import (presets) normalise too', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final tenant = c.read(tenantIdProvider);
      final p = _product(tenant);
      await c.read(productServiceProvider).importAll([p]);
      expect(c.read(fakeDatabaseProvider).products.singleWhere((x) => x.id == p.id).name, uProduct);
      await c.read(productServiceProvider).update(p.copyWith(name: 'ေရသန္႔ 1L', updatedAt: DateTime.utc(2026, 11, 3)));
      expect(c.read(fakeDatabaseProvider).products.singleWhere((x) => x.id == p.id).name, 'ရေသန့် 1L');
    });

    test('quick-sale item name in the cart', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(cartProvider.notifier).addQuick(500, zgProduct);
      expect(c.read(cartProvider).lines.single.name, uProduct);
    });

    test('form validation measures the Unicode text (SyncLimitsData.normalize)', () {
      final limits = bundledLimits();
      expect(limits.normalize('customers.name', ' $zgName '), uName);
      expect(limits.normalize('customers.name', uName), uName);
      expect(limits.normalize('products.barcode', '8850999150003'), '8850999150003');
    });

    test('Unicode input is saved byte for byte (nothing "converted")', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final cust = _customer(c.read(tenantIdProvider), name: 'ယခု မိုးရွာနေပါသလား');
      await c.read(customerServiceProvider).create(cust.copyWith(address: () => uAddress, note: () => uNote));
      final saved = c.read(fakeDatabaseProvider).customers.singleWhere((x) => x.id == cust.id);
      expect((saved.name, saved.address, saved.note), ('ယခု မိုးရွာနေပါသလား', uAddress, uNote));
    });
  });

  test('Drift: the outbox row that syncs carries the Unicode name', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    await c.read(customerServiceProvider).create(_customer(shop.tenantId));
    final rows = rowsOf((await outbox(db)).last);
    expect(rows.toString(), contains(uName));
    expect(rows.toString(), isNot(contains(zgName)));
  });

  test('register: the shop name goes to the server in Unicode', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final store = MemorySecureStore();
    final api = FakeAuthApi();
    final boot = await bootstrap(db, store);
    final c = ProviderContainer(overrides: [
      ...driftOverrides(db, boot, store),
      authApiProvider.overrideWithValue(api),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
    ]);
    addTearDown(c.dispose);
    await c
        .read(authControllerProvider.notifier)
        .register(rawPhone: '0971234567', otp: '123456', shopName: zgShop, templateId: 'grocery', pin: '111111');
    expect(api.calls.last, 'register:+95971234567:123456:$uShop:grocery');
  });

  group('screens', () {
    Future<ProviderContainer> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
          overrides: [...fakeRepositoryOverrides, initialLimitsProvider.overrideWithValue(bundledLimits())]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('Add customer form: typed in Zawgyi → listed in Unicode, found by both spellings', (tester) async {
      final c = await boot(tester);
      c.read(appRouterProvider).go('${Routes.customers}/new');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, zgName);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('သိမ်းမယ်').last);
      await tester.tap(find.text('သိမ်းမယ်').last);
      await tester.pumpAndSettle();
      expect(c.read(fakeDatabaseProvider).customers.where((x) => x.name == uName), hasLength(1));

      c.read(appRouterProvider).go(Routes.customers);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('အားလုံး').first); // the filter chips scroll sideways
      await tester.pumpAndSettle();
      await tester.tap(find.text('အားလုံး').first);
      await tester.pumpAndSettle();
      for (final q in [uName, zgName, 'မောင်']) {
        await tester.enterText(find.byType(EditableText).first, q);
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byType(CustomerRow), matching: find.text(uName)), findsOneWidget, reason: 'query $q');
      }
    });
  });
}
