// QA round 9 — live: BUG-26 (7df5f1f) against the REAL API and a scratch database (two phones of one shop).
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_OTP=123456 \
//   [ZAYPOS_LIVE_SQL_DB=ZayPOS_QA_…  (optional: blanks one issue's Data with sqlcmd in the zaypos-sql container)] \
//   flutter test test/qa/live_qa_round9_test.dart
//
// Owner: "issue/rejection messages must be built in the app in Burmese from the issue type plus structured fields
// (barcode, product names, IMEI, amounts) … keep the old text field for compatibility … No internal names on screen."
// Every issue kind the server raises (UnitApplier.Issue) is provoked through the app's own services (or, for the three
// that only a broken / reinstalled / fast-clock phone produces, by editing the waiting outbox unit — the same bytes such
// a phone would send); then both phones pull, and the message the screens show (issueMessage / rejectMessage, the
// functions sync_review_screen.dart and rejected_unit_screen.dart call) is checked for the right names / numbers and
// for English outside the owner's allow-list. Rejected units: the server's code + data are stored (outbox.rejectCode).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../live_removed_phone_sign_in.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/sync/wire.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';
import 'package:zaypos_app/features/inventory/domain/stock_movement.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';
import 'package:zaypos_app/features/products/domain/product_modules.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';
import 'package:zaypos_app/features/sync/domain/sync_labels.dart';

import '../drift_helpers.dart';

const _allowedLatin = {
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch',
  'zaypos', 'ks', 'ml', 'l', 'kg', 'xx', 'xxx',
};

/// English words outside the allow-list once [data] (user data) is removed.
List<String> english(String text, Set<String> data) {
  var s = text;
  for (final d in ([...data]..sort((a, b) => b.length.compareTo(a.length)))) {
    s = s.replaceAll(d, '');
  }
  return RegExp(r'[A-Za-z]{2,}').allMatches(s).map((m) => m.group(0)!).where((w) => !_allowedLatin.contains(w.toLowerCase()))
      .toList();
}

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final otp = env['ZAYPOS_LIVE_OTP'];
  final sqlDb = env['ZAYPOS_LIVE_SQL_DB'];
  final skip = base == null || phone == null || otp == null ? 'set ZAYPOS_LIVE_API/PHONE/OTP' : null;

  test('live BUG-26: every issue kind the server raises → Burmese message with the right names / numbers on BOTH phones; '
      'rejected units → Burmese reason from code + data; an issue without data → the shorter Burmese sentence', () async {
    final dbs = <AppDatabase>[];
    final containers = <ProviderContainer>[];
    addTearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      for (final d in dbs) {
        await d.close();
      }
    });

    Future<ProviderContainer> phoneApp() async {
      final db = memoryDb();
      dbs.add(db);
      final store = MemorySecureStore();
      final boot = await bootstrap(db, store);
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, boot, store),
        apiBaseUrlProvider.overrideWithValue(base!),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      ]);
      containers.add(c);
      return c;
    }

    AppDatabase dbOf(ProviderContainer c) => dbs[containers.indexOf(c)];
    Future<List<OutboxRow>> waiting(ProviderContainer c) => outbox(dbOf(c));

    Future<void> sync(ProviderContainer c, {bool allowRejected = false}) async {
      final e = c.read(syncEngineProvider);
      await e.syncNow(manual: true);
      expect(e.snapshot.lastError, isNull, reason: 'sync failed: ${e.snapshot.lastError}');
      if (!allowRejected) {
        final left = await waiting(c);
        expect(left.map((o) => '${o.kind}: ${o.status.name} ${o.rejectReason ?? ''}'), isEmpty,
            reason: 'every unit must be accepted by the real server');
      }
    }

    /// Edits the last waiting unit like a broken / reinstalled / fast-clock phone would have sent it.
    Future<void> editLastUnit(ProviderContainer c, void Function(Map<String, dynamic> rows) edit, {int? clientTime}) async {
      final db = dbOf(c);
      final last = (await waiting(c)).last;
      final rows = rowsOf(last);
      edit(rows);
      await (db.update(db.outbox)..where((o) => o.seq.equals(last.seq))).write(OutboxCompanion(
            rowsJson: Value(jsonEncode(rows)),
            clientTime: clientTime == null ? const Value.absent() : Value(clientTime),
          ));
    }

    final a = await phoneApp();
    await a.read(authControllerProvider.notifier).register(
        rawPhone: phone!, otp: otp!, shopName: 'QA live r9', templateId: 'phone', pin: '246810');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    final t = nowUtc();
    Product product(String name, {String? barcode, int price = 1500}) => Product(id: newId(), tenantId: tid, name: name,
        cost: 1000, price: price, category: 'x', barcode: barcode, tint: 0xFFDBEAFE, initial: 'Q', createdAt: t,
        updatedAt: t);
    Future<void> create(ProviderContainer c, Product p, {int units = 0, List<String> imeis = const []}) =>
        c.read(productServiceProvider).create(p,
            serials: [
              for (final s in imeis)
                ProductSerial(id: newId(), tenantId: tid, productId: p.id, serial: s, status: SerialStatus.inStock,
                    createdAt: t, updatedAt: t),
            ],
            initialStock: units == 0 && imeis.isEmpty
                ? const []
                : [restockMovement(tenantId: tid, productId: p.id, qtyMilli: Qty.units(units + imeis.length))]);
    Future<Sale> sell(ProviderContainer c, Product p, {String? serialId, PaymentMethod method = PaymentMethod.cash,
            String? customerId}) =>
        c.read(checkoutServiceProvider).checkout(CheckoutRequest(lines: [
          (productId: p.id, variantId: null, batchId: null, serialId: serialId, name: p.name, qtyMilli: 1000,
              price: p.price, cost: p.cost),
        ], method: method, customerId: customerId));
    Future<String> serialId(ProviderContainer c, String imei) async {
      final db = dbOf(c);
      return (await (db.select(db.productSerials)..where((s) => s.serial.equals(imei))).get())
          .firstWhere((s) => s.status == SerialStatus.inStock)
          .id;
    }

    // ---- shared products, then phone B
    const dupCode = '8850000099101';
    final coke = product('QA r9 Coke can', barcode: dupCode), pepsi = product('QA r9 Pepsi can', barcode: dupCode);
    await create(a, coke, units: 5);
    await create(a, pepsi, units: 5); // → duplicateBarcode
    final tiger = product('QA r9 Tiger beer');
    await create(a, tiger, units: 1);
    const soldTwice = '359930000000002';
    final galaxy = product('QA r9 Galaxy A15', price: 450000);
    await create(a, galaxy, imeis: [soldTwice]);
    final rice = product('QA r9 rice sack', price: 75500);
    await create(a, rice, units: 3);
    final mama = Customer(id: newId(), tenantId: tid, name: 'QA r9 Ma Ma', phone: '09790009901', creditLimit: 50000,
        createdAt: t, updatedAt: t);
    await a.read(customerServiceProvider).create(mama);
    await sync(a);

    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '246810');
    await sync(b);

    // ---- duplicateSerial: both phones receive the same box on different products, offline
    const twin = '359930000000001';
    final ip13 = product('QA r9 iPhone 13', price: 900000), ip13p = product('QA r9 iPhone 13 Pro', price: 1200000);
    await create(a, ip13, imeis: [twin]);
    await create(b, ip13p, imeis: [twin]);
    // ---- serialDoubleSold + negativeStock: both phones sell the same IMEI / the last can, offline
    await sell(a, galaxy, serialId: await serialId(a, soldTwice));
    await sell(b, galaxy, serialId: await serialId(b, soldTwice));
    await sell(a, tiger);
    await sell(b, tiger);
    await sync(a);
    await sync(b);

    // ---- creditLimitExceeded (A sells 75,500 Ks on credit, limit 50,000 Ks)
    await sell(a, rice, method: PaymentMethod.debt, customerId: mama.id);
    await sync(a);
    // ---- totalMismatch (a phone that sends a wrong total)
    await sell(a, coke);
    await editLastUnit(a, (r) => (r[WireTable.sales] as List).first['total'] = 1400);
    await sync(a);
    // ---- duplicateReceiptNo (a reinstalled phone reusing a receipt number already on the server)
    final firstSaleNo = (await dbOf(a).select(dbOf(a).sales).get()).first.no;
    await sell(a, coke);
    await editLastUnit(a, (r) => (r[WireTable.sales] as List).first['no'] = firstSaleNo);
    await sync(a);
    // ---- clockSkew (the phone's clock 31 min ahead)
    await a.read(customerServiceProvider).create(Customer(id: newId(), tenantId: tid, name: 'QA r9 Ko Aung',
        phone: '09790009902', createdAt: t, updatedAt: t));
    await editLastUnit(a, (_) {}, clientTime: nowUtc().add(const Duration(minutes: 31)).millisecondsSinceEpoch);
    await sync(a);

    // ---- optional: an issue row from before the server stored Data (null) — the shorter sentence
    String? blankedId;
    if (sqlDb != null) {
      final dup = (await dbOf(a).select(dbOf(a).syncIssues).get()).firstWhere((i) => i.kind == 'duplicateBarcode');
      final r = await Process.run('docker', [
        'exec', 'zaypos-sql', '/opt/mssql-tools18/bin/sqlcmd', '-C', '-S', 'localhost', '-U', 'sa', '-P', 'Zaypos!Dev2026',
        '-d', sqlDb, '-Q', "SET NOCOUNT ON; UPDATE dbo.SyncIssues SET Data = NULL, UpdatedAt = SYSUTCDATETIME() "
            "WHERE Id = '${dup.id}' AND TenantId = '$tid'",
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      blankedId = dup.id;
    }
    await sync(a);
    await sync(b);

    // ---- the issues and their messages, on both phones
    const userData = {
      'QA r9 Coke can', 'QA r9 Pepsi can', 'QA r9 iPhone 13 Pro', 'QA r9 iPhone 13', 'QA r9 Galaxy A15', 'QA r9 Tiger beer',
      'QA r9 Ma Ma',
    };
    final expected = <String, List<String>>{
      'duplicateBarcode': [dupCode, '“QA r9 Pepsi can”', '“QA r9 Coke can”'],
      'duplicateSerial': [twin, '“QA r9 iPhone 13 Pro”', '“QA r9 iPhone 13”'],
      'serialDoubleSold': [soldTwice, '“QA r9 Galaxy A15”'],
      'negativeStock': ['-၁'],
      'creditLimitExceeded': ['“QA r9 Ma Ma”', '75,500 Ks', '50,000 Ks'],
      'totalMismatch': ['1,500 Ks'],
      'duplicateReceiptNo': [firstSaleNo, '$firstSaleNo*2'],
      'clockSkew': ['မိနစ်'],
    };
    final report = StringBuffer();
    for (final (name, c) in [('A', a), ('B', b)]) {
      final issues = await dbOf(c).select(dbOf(c).syncIssues).get();
      expect(issues.map((i) => i.kind).toSet(), containsAll(expected.keys), reason: 'phone $name');
      for (final i in issues) {
        final msg = issueMessage(i.kind, i.data);
        report.writeln('phone $name · ${i.kind}\n  data: ${i.data}\n  detail: ${i.detail}\n  shown: ${issueKindLabel(i.kind)} — $msg');
        final words = english('${issueKindLabel(i.kind)} $msg', {...userData, firstSaleNo, '$firstSaleNo*2'});
        expect(words, isEmpty, reason: 'phone $name ${i.kind}: "$msg"');
        expect(msg, isNot(contains(i.detail)));
        // A / B pulled this issue before it was blanked; a pulled null does not clear the local copy (TC-SYNC-NEW-14),
        // so the "old row" check is done on a NEW phone C below.
        if (i.id == blankedId) continue;
        expect(i.data, isNotNull, reason: 'phone $name ${i.kind}: the server sends structured fields');
        for (final want in expected[i.kind] ?? const <String>[]) {
          if (i.kind == 'negativeStock' && !msg.contains('Tiger') && !msg.contains('Galaxy')) {
            fail('negativeStock without the product name: $msg');
          }
          expect(msg, contains(want), reason: 'phone $name ${i.kind}');
        }
      }
    }

    // ---- an issue row without Data (as written before this server version): a NEW phone C downloads it
    if (blankedId != null) {
      final c3 = await phoneApp();
      await c3.read(authControllerProvider.notifier).login(phone, '246810');
      await sync(c3);
      final old = (await dbOf(c3).select(dbOf(c3).syncIssues).get()).singleWhere((i) => i.id == blankedId);
      final msg = issueMessage(old.kind, old.data);
      report.writeln('phone C · ${old.kind} (Data NULL on the server)\n  data: ${old.data}\n  shown: $msg');
      expect(old.data, isNull);
      expect(msg, startsWith('ဒီ Barcode ကို ပစ္စည်းတွေမှာ'), reason: 'old row → the shorter Burmese sentence');
      expect(english(msg, const {}), isEmpty);
    }

    // ---- TC-SYNC-NEW-14 (found this round): phone B clears Coke's barcode (a newer edit) → A must lose it too
    // (phase3-sync.md §5.3 "replace only if pulled.updatedAt >= local.updatedAt"). Checked at the very end.
    final onB = (await (dbOf(b).select(dbOf(b).products)..where((p) => p.id.equals(coke.id))).getSingle());
    await b.read(productServiceProvider).update(coke.copyWith(barcode: () => null, updatedAt: onB.updatedAt));
    await sync(b);
    await sync(a);
    final serverBarcode = await Process.run('docker', [
      'exec', 'zaypos-sql', '/opt/mssql-tools18/bin/sqlcmd', '-C', '-S', 'localhost', '-U', 'sa', '-P', 'Zaypos!Dev2026',
      '-d', sqlDb ?? 'none', '-h', '-1', '-Q', "SET NOCOUNT ON; SELECT ISNULL(Barcode, '<NULL>') FROM dbo.Products WHERE Id = '${coke.id}'",
    ]);
    final cokeOnA = await (dbOf(a).select(dbOf(a).products)..where((p) => p.id.equals(coke.id))).getSingle();
    final cokeOnB = await (dbOf(b).select(dbOf(b).products)..where((p) => p.id.equals(coke.id))).getSingle();
    final cleared = 'server: ${'${serverBarcode.stdout}'.trim()} · B: ${cokeOnB.barcode} · A: ${cokeOnA.barcode} '
        '(A updatedAt ${cokeOnA.updatedAt.toIso8601String()}, B ${cokeOnB.updatedAt.toIso8601String()})';
    // ignore: avoid_print
    print('TC-SYNC-NEW-14 barcode cleared on B → $cleared');

    // ---- rejected units: A a too-long product name, B a barcode with Myanmar letters
    await create(a, product('QA r9 long'));
    await editLastUnit(a, (r) => (r[WireTable.products] as List).first['name'] = 'QA r9 ${'x' * 200}');
    await sync(a, allowRejected: true);
    // products.barcode rejects non-ASCII (SyncLimits.cs:91; customers.phone only drops it, :98)
    await create(b, product('QA r9 bad barcode', barcode: '8850000099199'));
    await editLastUnit(b, (r) => (r[WireTable.products] as List).first['barcode'] = 'ဘား၈၈၅');
    await sync(b, allowRejected: true);
    for (final (name, c, code, words) in [
      ('A', a, 'fieldTooLong', ['“အမည်”', 'စာလုံး ၁၅၀ လုံး']),
      ('B', b, 'fieldNotAscii', ['“Barcode”', 'ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ']),
    ]) {
      final rej = (await waiting(c)).where((o) => o.status == OutboxStatus.rejected).toList();
      expect(rej, hasLength(1), reason: 'phone $name');
      final o = rej.single;
      final msg = rejectMessage(o.rejectCode, o.rejectData);
      report.writeln('phone $name · rejected ${o.kind}\n  code: ${o.rejectCode} data: ${o.rejectData}\n'
          '  reason: ${o.rejectReason}\n  shown: ${unitSummary(o.kind, rowsOf(o))} — $msg');
      expect(o.rejectCode, code, reason: 'phone $name');
      for (final w in words) {
        expect(msg, contains(w), reason: 'phone $name: $msg');
      }
      expect(english(msg, const {}), isEmpty);
      expect(msg, isNot(contains(o.rejectReason!)));
    }
    // ignore: avoid_print
    print('BUG-26 live messages:\n$report');
    expect(cokeOnB.barcode, isNull);
    expect(cokeOnA.barcode, isNull, reason: 'TC-SYNC-NEW-14: $cleared');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));
}
