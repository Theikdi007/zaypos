// QA round 7 — real local database (in-memory Drift):
// - TC-PROD-NEW-32: a product saved WITH a photo through the real Add Product form → the outbox gets exactly the same
//   ONE upsertProduct unit as without a photo (no photo field / bytes on the wire: "stored locally only … not synced");
//   phone B (its own database, no photo files) shows the initial.
// - TC-PROD-NEW-33: BUG-24 (8eab56b) edge cases on Drift: trade-in resold, then void sale 1 → no serial row sent back
//   to inStock, no voidReturn for the phone; un-void sale 1 → no −1; void sale 2 → the resold row returns (+1) once.
//   BUG-24 fix text: "taken back = a NEWER row with the same IMEI exists (on any product), whatever its status now".
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/inventory/application/stock_service.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/data/product_photos.dart';
import 'package:zaypos_app/features/products/data/product_repository.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/application/void_sale_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_screens_test.dart' show settle;

class _Picker implements PhotoPicker {
  Uint8List? next;
  @override
  Future<Uint8List?> pick(PhotoSource source) async => next;
}

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  testWidgets('TC-PROD-NEW-32 Drift: Add Product with a photo → ONE upsertProduct unit, no photo on the wire; phone B '
      'without the file shows the initial', (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi();
    for (var i = 0; i < 200; i++) {
      api.pushErrors.add(const ApiError.network()); // offline: units stay in the outbox
    }
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final files = MemoryPhotoFiles();
    final picker = _Picker();
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          photoFilesProvider.overrideWithValue(files),
          photoCompressorProvider.overrideWithValue((raw) async => compressPhoto(raw)),
          photoPickerProvider.overrideWithValue(picker),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);
    await tester.runAsync(() => adb.delete(adb.outbox).go());

    c.read(appRouterProvider).go(Routes.addProduct);
    await settle(tester);
    final r = Random(5);
    final im = img.Image(width: 800, height: 600);
    for (final p in im) {
      p
        ..r = r.nextInt(256)
        ..g = r.nextInt(256)
        ..b = r.nextInt(256);
    }
    picker.next = img.encodePng(im);
    await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
    await settle(tester);
    await tester.tap(find.text('ပုံ ရွေးမယ်'));
    await settle(tester);
    Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
    await tester.enterText(field('productName'), 'QA R7 D photo');
    await tester.enterText(field('price'), '800');
    await tester.runAsync(() async {
      await tester.tap(find.text('သိမ်းမယ်').last);
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await settle(tester);
    expect(find.text('ပစ္စည်းအသစ်'), findsNothing, reason: 'saved');

    final p = (await tester.runAsync(() => (adb.select(adb.products)..where((x) => x.name.equals('QA R7 D photo'))).getSingle()))!;
    expect(files.bytes.keys, [p.id], reason: 'photo kept on this phone');
    expect(files.bytes[p.id]!.length, lessThanOrEqualTo(maxPhotoBytes));
    final units = (await tester.runAsync(() => outbox(adb)))!;
    expect(units.map((u) => u.kind), ['upsertProduct'], reason: 'ONE unit, as without a photo');
    final rows = rowsOf(units.single);
    final prod = (rows[WireTable.products] as List).cast<Map>().single;
    expect(prod.keys.where((k) => '$k'.toLowerCase().contains('photo') || '$k'.toLowerCase().contains('image')), isEmpty);
    final json = jsonEncode(rows);
    expect(json.length, lessThan(4000), reason: 'no image bytes in the unit (${json.length} chars)');
    // ignore: avoid_print
    print('TC-PROD-NEW-32 product keys: ${prod.keys.toList()}');

    // Phone B: the same product row, its own (empty) photo store → POS shows the initial, no photo widget.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
    final bdb = memoryDb();
    addTearDown(() => tester.runAsync(bdb.close));
    final (b, bs) = (await tester.runAsync(() => driftContainer(bdb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          photoFilesProvider.overrideWithValue(MemoryPhotoFiles()),
        ])))!;
    addTearDown(b.dispose);
    await tester.runAsync(() => SyncStore(bdb, tenantId: bs.tenantId, deviceId: bs.deviceId).markInitialSyncDone());
    await tester.runAsync(() => b.read(productServiceProvider).create(Product(
        id: p.id, tenantId: bs.tenantId, name: p.name, cost: p.cost, price: p.price, category: p.category, tint: p.tint,
        initial: 'Q', createdAt: t0, updatedAt: t0)));
    await tester.pumpWidget(UncontrolledProviderScope(container: b, child: const ZayPosApp()));
    await settle(tester);
    b.read(appRouterProvider).go(Routes.pos);
    await settle(tester);
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await settle(tester);
    }
    expect(find.text('QA R7 D photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('productPhoto')), findsNothing, reason: 'phone B has no photo: initial tile');
    expect(find.text('Q'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
  });

  test('TC-PROD-NEW-33 Drift (BUG-24): trade-in resold, void sale 1 → nothing back; un-void sale 1 → no −1; void sale 2 → '
      'the resold row back once (+1)', () async {
    final adb = memoryDb();
    addTearDown(adb.close);
    final (c, shop) = await driftContainer(adb, seed: false);
    addTearDown(c.dispose);
    final repo = c.read(productRepositoryProvider);
    const imei = '358000000000071';
    final p = Product(id: newId(), tenantId: shop.tenantId, name: 'QA R7 D phone', cost: 1, price: 2, category: 'x',
        tint: 0, initial: 'D', createdAt: t0, updatedAt: t0);
    final old = ProductSerial(id: newId(), tenantId: shop.tenantId, productId: p.id, serial: imei,
        status: SerialStatus.inStock, createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, serials: [old], initialStock: [
      restockMovement(tenantId: shop.tenantId, productId: p.id, qtyMilli: Qty.units(1)),
    ]);
    Future<Sale> sellRow(String serialId) => c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: serialId, name: p.name, qtyMilli: 1000, price: 2, cost: 1),
        ], method: PaymentMethod.cash));
    Future<int> stock() async => (await (adb.select(adb.stockMovements)
              ..where((m) => m.productId.equals(p.id) & m.deletedAt.isNull()))
            .get())
        .fold<int>(0, (a, m) => a + m.qtyMilli);
    Future<String> state() async {
      final rows = await (adb.select(adb.productSerials)..where((s) => s.serial.equals(imei))).get();
      final o = rows.singleWhere((s) => s.id == old.id), n = rows.singleWhere((s) => s.id != old.id);
      return 'old ${o.status.name}, new ${n.status.name}, inStock ${await repo.watchInStockSerialValues().first}, '
          'stock ${Qty.format(await stock())}';
    }

    final sale1 = await sellRow(old.id);
    await c.read(stockServiceProvider).receive(productId: p.id, qtyMilli: Qty.units(1), serials: [imei]);
    final fresh = (await (adb.select(adb.productSerials)..where((s) => s.serial.equals(imei) & s.id.equals(old.id).not()))
            .getSingle())
        .id;
    final sale2 = await sellRow(fresh);
    expect(await state(), 'old sold, new sold, inStock {}, stock 0');

    await adb.delete(adb.outbox).go();
    await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
    final v = rowsOf((await outbox(adb)).single);
    final vSerials = ((v[WireTable.productSerials] as List?) ?? const []).cast<Map>();
    final vMoves = ((v[WireTable.stockMovements] as List?) ?? const []).cast<Map>();
    expect(vSerials.where((s) => s['status'] == 'inStock'), isEmpty, reason: 'no IMEI row sent back to inStock');
    expect(vMoves.where((m) => m['productId'] == p.id), isEmpty, reason: 'no voidReturn for the resold phone');
    expect(await state(), 'old sold, new sold, inStock {}, stock 0', reason: 'void sale 1');

    await c.read(voidSaleServiceProvider).setVoided(sale1.id, false);
    expect(await state(), 'old sold, new sold, inStock {}, stock 0', reason: 'un-void sale 1: no −1');

    await c.read(voidSaleServiceProvider).setVoided(sale2.id, true);
    expect(await state(), 'old sold, new inStock, inStock {$imei}, stock 1', reason: 'void sale 2: customer 2 returned it');

    await c.read(voidSaleServiceProvider).setVoided(sale1.id, true);
    expect(await state(), 'old sold, new inStock, inStock {$imei}, stock 1', reason: 'void sale 1 again: still once');
  });
}
