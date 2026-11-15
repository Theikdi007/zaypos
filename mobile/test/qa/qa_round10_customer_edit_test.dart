// QA round 10 — found while verifying BUG-31: the owner's live check asks to "clear … credit limit on phone B", and the
// developer notes "the app has NO customer edit screen". The customer's debt screen ("အကြွေးစာရင်း") nevertheless shows a
// pencil button labelled "ပြင်ဆင်ရန်" (edit). debt_screen.dart: `AppIconButton(icon: AppIcons.edit, semanticLabel:
// 'ပြင်ဆင်ရန်', onPressed: () {})` — unchanged since d99efb7 (Phase 1). Add Customer promises a credit-limit warning
// (BUG-7), so a limit typed wrong, or a phone number typed wrong, can never be corrected or removed on any phone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import '../helpers.dart';
import '../sync_limits_test.dart' show bundledLimits;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('TC-DEBT-NEW-6 customer screen: the "ပြင်ဆင်ရန်" (edit) button opens an edit form for the customer (name, '
      'phone, credit limit can be changed / cleared)', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    final t = DateTime.utc(2026, 11, 1);
    final cu = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'QA R10 ဒေါ်မြ', phone: '09790010005',
        creditLimit: 50000, createdAt: t, updatedAt: t);
    await c.read(customerServiceProvider).create(cu);
    c.read(appRouterProvider).go(Routes.customer(cu.id));
    await tester.pumpAndSettle();
    expect(find.text('အကြွေးစာရင်း'), findsOneWidget);
    final edit = find.bySemanticsLabel('ပြင်ဆင်ရန်');
    expect(edit, findsWidgets, reason: 'the pencil button is on screen');
    await tester.tap(edit.first);
    await tester.pumpAndSettle();
    // Developer edit, owner-approved (2026-11-14; QA reviews in round 11): the app opens edit screens with
    // context.push, which does not change routerDelegate.currentConfiguration.uri in this go_router version, so the
    // route-change check became "the edit form opened" (its title + a field with the customer's name).
    final nameField = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == cu.name);
    expect((find.text('ဖောက်သည် ပြင်ဆင်ရန်').evaluate().isNotEmpty, nameField.evaluate().isNotEmpty), (true, true),
        reason: 'tapping "ပြင်ဆင်ရန်" did nothing (no edit form, no field with the customer\'s name)');
  });
}
