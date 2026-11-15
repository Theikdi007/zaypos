// QA round 8 — BUG-9 (fb520d9) beyond static scans: strings that are built at runtime or come from the server, and the
// new scan-lookup surfaces (e0ea12b). Same rule and allow-list as TC-UX-02 (owner, 2026-11-14): "allowed English =
// KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP, Stock, Sync (plus the brand, Ks / units and phone placeholders,
// which are not words). Everything else translated." Spec for server texts: docs/mobile/phase3-sync.md §"Errors from the
// server are ProblemDetails with a stable `code`; map codes to Burmese messages".
//
// What m/no_english_test.dart cannot see: it scans only string literals that contain a Burmese letter, so English that
// arrives at runtime (server issue details / reject reasons, raw feature keys) or English-only literals are not checked.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';
import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;
import '../sync_screens_test.dart' show drive, settle;

/// Same list as m/qa/qa_ux_test.dart (TC-UX-02) / m/qa/qa_round7_ux_test.dart (TC-UX-NEW-1).
const _allowedLatin = {
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch', // batch: owner 2026-11-14 (printed on medicine boxes)
  'zaypos', 'ks', 'ml', 'l', 'kg', 'xx', 'xxx',
  'xs', 'xl', 'xxl',
};

class _Scanner implements BarcodeScanner {
  String? next;
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async => next;
}

/// Latin words outside the allow-list in every Text on screen (or under [within]); product names in [data] are skipped.
List<String> badStrings(WidgetTester tester, {Finder? within, Set<String> data = const {}}) {
  final bad = <String>{};
  final texts = within == null ? find.byType(Text) : find.descendant(of: within, matching: find.byType(Text));
  for (final w in tester.widgetList<Text>(texts)) {
    var s = w.data ?? w.textSpan?.toPlainText() ?? '';
    for (final d in data) {
      s = s.replaceAll(d, '');
    }
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(s).map((m) => m.group(0)!.toLowerCase());
    final unknown = words.where((w) => !_allowedLatin.contains(w)).toSet().toList();
    if (unknown.isNotEmpty) bad.add('"${w.data ?? w.textSpan?.toPlainText()}" (English: ${unknown.join(', ')})');
  }
  return bad.toList();
}

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  testWidgets('TC-UX-NEW-3 server texts on "စစ်ရန်" and the rejected-unit screen, and a rejected setFeatures unit: no English',
      (tester) async {
    final adb = memoryDb();
    addTearDown(() => tester.runAsync(adb.close));
    final api = FakeSyncApi()
      ..outcome = ((_) => UnitOutcome.rejected)
      // SyncLimits.cs line 33 format (what the real server answers for a bad feature key / text)
      ..rejectReason = 'tenantFeatures.featureKey must not be empty.';
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (c, shop) = (await tester.runAsync(() => driftContainer(adb, seed: false, overrides: [
          syncApiProvider.overrideWithValue(api),
          connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
        ])))!;
    addTearDown(c.dispose);
    await tester.runAsync(() => SyncStore(adb, tenantId: shop.tenantId, deviceId: shop.deviceId).markInitialSyncDone());
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await settle(tester);

    // A pulled duplicateBarcode issue, detail exactly as UnitApplier.CheckBarcodesAsync writes it
    // (`$"Barcode {barcode} is also used by: {names}."`; the live run m/qa/live_qa_round8_test.dart prints the real one).
    final now = DateTime.now().toUtc();
    await tester.runAsync(() => adb.into(adb.syncIssues).insert(SyncIssuesCompanion.insert(
          id: newId(), tenantId: shop.tenantId, createdAt: now, updatedAt: now, kind: 'duplicateBarcode',
          entityTable: 'Products', entityId: newId(), detail: 'Barcode 8850000088001 is also used by: ကိုကာကိုလာ.',
        )));
    // A feature switched in Settings, rejected by the server.
    c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.expiryBatch, true);
    await settle(tester);
    await drive(tester, () => c.read(syncEngineProvider).syncNow(manual: true));

    final found = <String, List<String>>{};
    c.read(appRouterProvider).go(Routes.syncReview);
    await settle(tester);
    final review = badStrings(tester, data: {'ကိုကာကိုလာ'});
    if (review.isNotEmpty) found['/settings/sync-review'] = review;

    final seq = (await tester.runAsync(() => outbox(adb)))!.single.seq;
    c.read(appRouterProvider).push(Routes.rejectedUnit(seq));
    await settle(tester);
    final unit = badStrings(tester);
    if (unit.isNotEmpty) found['rejected unit'] = unit;

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.pump(const Duration(minutes: 30));
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n'));
  });

  testWidgets('TC-UX-NEW-4 new scan surfaces (duplicate warning, POS picker, IMEI snackbar) and screens the TC-UX-02 walk '
      'does not open (devices, products without a price): no English', (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      barcodeScannerProvider.overrideWithValue(_Scanner()),
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    c.read(shopTemplateProvider.notifier).select('phone');
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final tid = c.read(tenantIdProvider);
    Product p(String name, String? barcode, int price) => Product(id: newId(), tenantId: tid, name: name, cost: 1, price: price,
        category: 'x', barcode: barcode, tint: 0xFFDBEAFE, initial: 'Q', createdAt: t0, updatedAt: t0);
    final a = p('ဖုန်းအိတ်', '8850000008600', 5000), b = p('အားသွင်းကြိုး', '8850000008600', 0);
    final ph = p('ဖုန်းအသစ်', null, 450000);
    await c.read(productServiceProvider).create(a);
    await c.read(productServiceProvider).create(b);
    await c.read(productServiceProvider).create(ph, serials: [
      ProductSerial(id: newId(), tenantId: tid, productId: ph.id, serial: '359800000008601', status: SerialStatus.inStock,
          createdAt: t0, updatedAt: t0),
    ], initialStock: [restockMovement(tenantId: tid, productId: ph.id, qtyMilli: Qty.units(1))]);
    final found = <String, List<String>>{};
    void check(String where, {Finder? within}) {
      final bad = badStrings(tester, within: within);
      if (bad.isNotEmpty) found[where] = bad;
    }

    Future<void> burst(String s) async {
      for (final ch in s.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(ch.codeUnitAt(0)), character: ch);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
    await tester.enterText(field('productName'), 'ဖုန်းကာ');
    await tester.enterText(field('price'), '900');
    await tester.enterText(field('barcode'), '8850000008600');
    await tester.ensureVisible(find.text('သိမ်းမယ်').last);
    await tester.tap(find.text('သိမ်းမယ်').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    check('duplicate-barcode dialog', within: find.byType(AlertDialog));
    await tester.tap(find.byKey(const ValueKey('duplicateBarcodeCancel')));
    await tester.pumpAndSettle();

    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
    await burst('8850000008600');
    expect(find.text('ဘယ်ပစ္စည်းလဲ?'), findsOneWidget);
    check('POS duplicate-barcode picker', within: find.byType(BottomSheet));
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    await burst('359800000008601');
    await burst('359800000008601');
    expect(find.byType(SnackBar), findsOneWidget);
    check('IMEI already-in-cart snackbar', within: find.byType(SnackBar));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    for (final r in [Routes.devices, Routes.productsNeedingPrice]) {
      c.read(appRouterProvider).go(r);
      await tester.pumpAndSettle();
      check(r);
    }
    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n'));
  });
}
