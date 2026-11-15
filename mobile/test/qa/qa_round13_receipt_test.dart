// QA round 13 — TC-SALE-NEW-1 (new): the receipt image of a VOIDED sale must say it is voided.
// Since 71dfd5b (BUG-40) the sale screen's "ပြေစာ ပို့မယ်" shares a receipt PNG for any sale, voided ones included.
// TC-SALE-01 expects a voided sale to be "Marked ပယ်ဖျက်ပြီး"; the sale screen shows the badge, the struck total and
// "ပယ်ဖျက်ပြီးပါပြီ။". A receipt that a customer receives must not look like a valid sale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';

import '../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-SALE-NEW-1 the shared receipt of a voided sale is marked "ပယ်ဖျက်" (image differs from the valid one)',
      (tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final sale = (await tester.runAsync(() => val(c, saleByIdProvider(SeedIds.sale1032))))!;
    final voided = sale.copyWith(voidedAt: () => DateTime.utc(2026, 11, 15, 12));
    expect(voided.voided, isTrue);

    // What renderReceiptPng draws (it renders exactly this widget off screen).
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptCard(sale: voided, shop: 'ဇေ စတိုး'))));
    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    // ignore: avoid_print
    print('TC-SALE-NEW-1 voided receipt texts: $texts');

    final valid = (await tester.runAsync(() => renderReceiptPng(tester.view, sale: sale, shop: 'ဇေ စတိုး')))!;
    final shared = (await tester.runAsync(() => renderReceiptPng(tester.view, sale: voided, shop: 'ဇေ စတိုး')))!;
    // ignore: avoid_print
    print('TC-SALE-NEW-1 PNG bytes valid=${valid.length} voided=${shared.length} identical=${_same(valid, shared)}');

    expect(find.textContaining('ပယ်ဖျက်'), findsWidgets, reason: 'the voided sale\'s receipt says it is voided');
    expect(_same(valid, shared), isFalse, reason: 'the shared image of a voided sale differs from the valid receipt');
  });
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
