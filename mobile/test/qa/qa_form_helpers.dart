// QA helpers for the Add Product / edit form "သက်တမ်း နှင့် Batch" section (owner decisions 2026-11-14:
// expiryAlertDays starts empty in Add Product; batch no. + expiry are required for tracked opening stock).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const expiryWarnKey = ValueKey('expiryWarn');
const noExpiryLabel = 'သက်တမ်း မမှတ်ပါ';
const warn30Label = 'ရက် ၃၀ အလို';

/// The label the "ကုန်ခါနီးရင် သတိပေးမယ်" select currently shows.
Finder expiryWarnShows(String label) => find.descendant(of: find.byKey(expiryWarnKey), matching: find.text(label));

Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

/// Opens the "ကုန်ခါနီးရင် သတိပေးမယ်" select and picks [label] (e.g. [warn30Label]).
Future<void> pickExpiryWarn(WidgetTester tester, String label) async {
  await _reveal(tester, find.byKey(expiryWarnKey));
  await tester.tap(find.byKey(expiryWarnKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Taps the Add Product "သက်တမ်းကုန်ရက်" field and picks [day] of the month shown (the current month) → OK.
Future<void> pickAddProductExpiry(WidgetTester tester, int day) async {
  final f = find.bySemanticsLabel('သက်တမ်းကုန်ရက်');
  await _reveal(tester, f);
  await tester.tap(f.last);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('$day')));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
