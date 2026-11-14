import 'dart:convert';

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
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'helpers.dart';
import 'sync_limits_test.dart' show bundledLimits;

/// BUG-33: "ပြင်ဆင်ရန်" on the debt screen opens the Add Customer form in edit mode (name, phone, address,
/// credit limit); same rules as Add, a duplicate phone is warned about; the edit syncs like other edits.
void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides,
      initialLimitsProvider.overrideWithValue(bundledLimits()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
    await tester.pumpAndSettle();
    return c;
  }

  Finder field(String label) => find.descendant(of: find.bySemanticsLabel(label), matching: find.byType(EditableText));
  Customer? stored(ProviderContainer c, String id) => c.read(customersProvider).value?.where((x) => x.id == id).firstOrNull;

  Future<void> openEdit(WidgetTester tester, ProviderContainer c, String id) async {
    c.read(appRouterProvider).go(Routes.customer(id));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('ပြင်ဆင်ရန်').first);
    await tester.pumpAndSettle();
  }

  testWidgets('edit: prefilled form, balance next to the limit, no opening balance; changes are saved; '
      'a limit below the balance is allowed', (tester) async {
    final c = await boot(tester);
    final t = DateTime.utc(2026, 11, 1);
    final cu = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'ဒေါ်မြ', phone: '09790010005',
        address: 'ရန်ကုန်', creditLimit: 50000, createdAt: t, updatedAt: t);
    await c.read(customerServiceProvider).create(cu, openingBalance: 30000);
    await openEdit(tester, c, cu.id);

    expect(find.text('ဖောက်သည် ပြင်ဆင်ရန်'), findsOneWidget);
    expect(tester.widget<EditableText>(field('အမည်')).controller.text, 'ဒေါ်မြ');
    expect(tester.widget<EditableText>(field('ဖုန်းနံပါတ်')).controller.text, '09790010005');
    expect(tester.widget<EditableText>(field('လိပ်စာ')).controller.text, 'ရန်ကုန်');
    expect(tester.widget<EditableText>(field('အကြွေး ကန့်သတ်ချက်')).controller.text, '50000');
    expect(find.descendant(of: find.byKey(const ValueKey('currentBalance')), matching: find.text('30,000 Ks')), findsOneWidget);
    expect(find.bySemanticsLabel('ယခင်အကြွေး'), findsNothing, reason: 'opening balance is a ledger entry: add only');

    await tester.enterText(field('အမည်'), 'ဒေါ်မြမြ');
    await tester.enterText(field('အကြွေး ကန့်သတ်ချက်'), '10000'); // below the 30,000 balance: allowed
    await tester.enterText(field('လိပ်စာ'), '');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    final after = stored(c, cu.id)!;
    expect((after.name, after.creditLimit, after.address, after.phone), ('ဒေါ်မြမြ', 10000, null, '09790010005'));
    expect(find.text('အကြွေးစာရင်း'), findsOneWidget, reason: 'back on the debt screen');
    final account = c.read(customerAccountProvider(cu.id)).value!;
    expect(account.balance, 30000, reason: 'the ledger is not touched');

    // clearing the limit = no limit
    await openEdit(tester, c, cu.id);
    await tester.enterText(field('အကြွေး ကန့်သတ်ချက်'), '');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    expect(stored(c, cu.id)!.creditLimit, isNull);
  });

  testWidgets('same rules as Add: an empty name is refused; a phone already used by another customer is warned about '
      '(add and edit) — cancel keeps the form, save anyway saves', (tester) async {
    final c = await boot(tester);
    final t = DateTime.utc(2026, 11, 1);
    final a = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'ကိုအေ', phone: '09790010006', createdAt: t, updatedAt: t);
    final b = Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'ကိုဘီ', phone: '09790010007', createdAt: t, updatedAt: t);
    await c.read(customerServiceProvider).create(a);
    await c.read(customerServiceProvider).create(b);

    await openEdit(tester, c, b.id);
    await tester.enterText(field('အမည်'), '');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('အမည် ထည့်ပါ။'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'ကိုဘီ'); // the name field (its label carries the error now)
    await tester.enterText(field('ဖုန်းနံပါတ်'), '၀၉၇၉၀၀၁၀၀၀၆'); // a's number, in Myanmar digits
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsOneWidget);
    expect(find.textContaining('“ကိုအေ”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duplicatePhoneCancel')));
    await tester.pumpAndSettle();
    expect(stored(c, b.id)!.phone, '09790010007');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duplicatePhoneSave')));
    await tester.pumpAndSettle();
    expect(stored(c, b.id)!.phone, '09790010006');

    // unchanged phone on edit: no warning even though a shares it now
    await openEdit(tester, c, b.id);
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsNothing);

    // Add Customer warns too
    c.read(appRouterProvider).go(Routes.addCustomer);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(0), 'ကိုစီ'); // name, then phone
    await tester.enterText(find.byType(EditableText).at(1), '09790010006');
    await tester.tap(find.text('သိမ်းမယ်'));
    await tester.pumpAndSettle();
    expect(find.text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ'), findsOneWidget);
  });

  test('Drift: the edit is ONE upsertCustomer unit with the whole row (a cleared limit is sent as null)', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final (c, shop) = await driftContainer(db, seed: false);
    addTearDown(c.dispose);
    final t = DateTime.utc(2026, 11, 1);
    final cu = Customer(id: newId(), tenantId: shop.tenantId, name: 'မမ', phone: '0912345678', creditLimit: 50000,
        createdAt: t, updatedAt: t);
    await c.read(customerServiceProvider).create(cu);
    await c.read(customerServiceProvider).update(cu.copyWith(name: 'မမလေး', creditLimit: () => null));
    final units = await db.select(db.outbox).get();
    expect(units.map((u) => u.kind), ['upsertCustomer', 'upsertCustomer']);
    final rows = jsonDecode(units.last.rowsJson) as Map<String, dynamic>;
    expect(rows.keys, ['customers'], reason: 'no ledger rows');
    final sent = (rows['customers'] as List).single as Map;
    expect((sent['name'], sent.containsKey('creditLimit'), sent['creditLimit']), ('မမလေး', true, null));
    final row = await (db.select(db.customers)..where((x) => x.id.equals(cu.id))).getSingle();
    expect((row.name, row.creditLimit, row.createdAt), ('မမလေး', null, t));
  });
}
