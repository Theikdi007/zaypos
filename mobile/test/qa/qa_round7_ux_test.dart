// QA round 7 — BUG-9 re-test beyond the round-1 route list (TC-UX-NEW-1): the same "no English on Burmese screens" rule
// (TC-UX-02: "No English left in Burmese screens except brand/payment names") applied to the template-specific forms and
// the sheets that TC-UX-02's route walk never opens — fashion Add Product / edit form, the POS size-colour sheet, the
// fashion "Stock ဖြည့်မယ်" sheet, pharmacy Add Product, the new scan / photo sheets — with a tall window so every row
// of the lists is built. The allow-list is exactly TC-UX-02's (m/qa/qa_ux_test.dart `_allowedLatin`).
// Also TC-UX-NEW-2: BUG-9 time format edges (00:00, 11:59, 12:00, 15:59, 16:00, 18:59, 19:00, 23:59).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/myanmar.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';

/// Same list as m/qa/qa_ux_test.dart (TC-UX-02), plus clothing size values.
const _allowedLatin = {
  // owner's list (2026-11-14, BUG-9)
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch', // batch: owner 2026-11-14 (printed on medicine boxes)
  'zaypos', 'ks', 'ml', 'l', 'kg', 'xx', 'xxx', // brand, currency / units, phone placeholders
  // round 7 additions — data, not UI words: clothing size values offered as chips (S M L XL XXL)
  'xs', 'xl', 'xxl',
};

/// Placeholder examples that are product / drug names (brand-like), not UI text.
const _examples = {'ဥပမာ - Paracetamol 500mg', 'ဥပမာ - Type-C အားသွင်းကြိုး'};

class _Scanner implements BarcodeScanner {
  String? next;
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async => next;
}

void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1);

  List<String> badStrings(WidgetTester tester, {Finder? within}) {
    final bad = <String>{};
    final texts = within == null ? find.byType(Text) : find.descendant(of: within, matching: find.byType(Text));
    for (final w in tester.widgetList<Text>(texts)) {
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (_examples.contains(s)) continue;
      final words = RegExp(r'[A-Za-z]{2,}').allMatches(s).map((m) => m.group(0)!.toLowerCase());
      final unknown = words.where((w) => !_allowedLatin.contains(w)).toList();
      if (unknown.isNotEmpty) bad.add('"$s" (English: ${unknown.join(', ')})');
    }
    return bad.toList();
  }

  testWidgets('TC-UX-NEW-1 template forms and sheets: no English left (BUG-9 beyond the TC-UX-02 routes)', (tester) async {
    tester.view.physicalSize = const Size(390, 3000); // tall: every list row is built
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scanner = _Scanner();
    final c = ProviderContainer(overrides: [...fakeRepositoryOverrides, barcodeScannerProvider.overrideWithValue(scanner)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final found = <String, List<String>>{};
    final sheet = find.byType(BottomSheet);
    void check(String where, {Finder? within}) {
      final b = badStrings(tester, within: within);
      if (b.isNotEmpty) found[where] = b;
    }

    // fashion product with sizes
    c.read(shopTemplateProvider.notifier).select('fashion');
    final p = Product(id: newId(), tenantId: c.read(tenantIdProvider), name: 'တီရှပ်', cost: 1, price: 2, category: 'x',
        barcode: '8850000000999', tint: 0xFFDBEAFE, initial: 'တ', createdAt: t0, updatedAt: t0);
    final m = ProductVariant(id: newId(), tenantId: p.tenantId, productId: p.id, size: 'M', color: 'အနက်', createdAt: t0, updatedAt: t0);
    await c.read(productServiceProvider).create(p, variants: [m], initialStock: [
      restockMovement(tenantId: p.tenantId, productId: p.id, qtyMilli: Qty.units(3), variantId: m.id, note: 'initial'),
    ]);
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    check('fashion Add Product');
    await tester.tap(find.byKey(const ValueKey('productPhotoButton')));
    await tester.pumpAndSettle();
    check('photo sheet', within: sheet);

    c.read(appRouterProvider).go(Routes.editProduct(p.id));
    await tester.pumpAndSettle();
    check('fashion edit form');

    c.read(appRouterProvider).go(Routes.products);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('restock-${p.id}')));
    await tester.pumpAndSettle();
    check('fashion "Stock ဖြည့်မယ်" sheet', within: sheet);

    c.read(appRouterProvider).go(Routes.pos);
    await tester.pumpAndSettle();
    if (find.text('ပစ္စည်းများ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ပစ္စည်းများ'));
      await tester.pumpAndSettle();
    }
    scanner.next = '8850000000999';
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await tester.pumpAndSettle();
    check('POS size/colour sheet (scanned)', within: sheet);
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    scanner.next = '1234567890';
    await tester.tap(find.byKey(const ValueKey('posScan')));
    await tester.pumpAndSettle();
    check('POS unknown-barcode sheet', within: sheet);

    c.read(shopTemplateProvider.notifier).select('pharmacy');
    c.read(appRouterProvider).go(Routes.addProduct);
    await tester.pumpAndSettle();
    check('pharmacy Add Product');

    c.read(appRouterProvider).go(Routes.settingsFeatures);
    await tester.pumpAndSettle();
    check('Settings (whole list built)');

    expect(found, isEmpty, reason: found.entries.map((e) => '${e.key}:\n  ${e.value.join('\n  ')}').join('\n'));
  });

  test('TC-UX-NEW-2 BUG-9 times: နံနက် 0–11, နေ့လယ် 12–15, ညနေ 16–18, ည 19–23, 12-hour digits, 2-digit minutes', () {
    String at(int h, int m) => timeLabel(DateTime(2026, 11, 14, h, m));
    expect(
      [at(0, 0), at(0, 5), at(11, 59), at(12, 0), at(15, 59), at(16, 0), at(18, 59), at(19, 0), at(23, 59)],
      ['နံနက် 12:00', 'နံနက် 12:05', 'နံနက် 11:59', 'နေ့လယ် 12:00', 'နေ့လယ် 3:59', 'ညနေ 4:00', 'ညနေ 6:59', 'ည 7:00', 'ည 11:59'],
    );
    // UTC input is shown in local time (sales are stored in UTC)
    final utc = DateTime.utc(2026, 11, 14, 9, 30);
    expect(timeLabel(utc), timeLabel(utc.toLocal()));
    expect(mmReceiptDate(DateTime(2026, 11, 10, 16, 5)), '၁၀ နိုဝင်ဘာ ၂၀၂၆ · ညနေ 4:05');
  });
}
