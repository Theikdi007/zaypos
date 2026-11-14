import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/main.dart';

import 'drift_helpers.dart';
import 'fake_sync_api.dart';
import 'helpers.dart';
import 'sync_screens_test.dart' show settle;

/// BUG-9: Burmese UI strings may only contain the owner's English words (2026-11-14):
/// KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP, Stock, Sync, Batch — plus things that are not words:
/// the brand, the currency / units and phone-number placeholders. Product-name examples are data.
const _allowed = {
  'kbzpay', 'wavepay', 'viber', 'excel', 'imei', 'barcode', 'pin', 'otp', 'stock', 'sync', 'batch', // batch: owner 2026-11-14 (printed on medicine boxes)
  'zaypos', 'ks', 'ml', 'kg', 'xx', 'xxx',
};
const _examples = {'ဥပမာ - Paracetamol 500mg', 'ဥပမာ - Type-C အားသွင်းကြိုး'};

/// Removes `${…}` (balanced braces, may contain quotes) so code inside strings is not read as text.
String _stripInterpolations(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s.startsWith(r'${', i)) {
      var depth = 1;
      i += 2;
      while (i < s.length && depth > 0) {
        if (s[i] == '{') depth++;
        if (s[i] == '}') depth--;
        i++;
      }
    } else {
      out.write(s[i++]);
    }
  }
  return out.toString();
}

void main() {
  test('no English words in Burmese string literals under lib/', () {
    final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'" '|' r'"((?:[^"\\\n]|\\.)*)"');
    final burmese = RegExp(r'[က-႟]');
    final interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
    final word = RegExp(r'[A-Za-z]{2,}');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = _stripInterpolations(lines[i].trimLeft());
        if (line.startsWith('//')) continue;
        for (final m in literal.allMatches(line)) {
          final s = m.group(1) ?? m.group(2)!;
          if (!burmese.hasMatch(s) || _examples.contains(s)) continue;
          final unknown = word
              .allMatches(s.replaceAll(interpolation, ''))
              .map((w) => w.group(0)!)
              .where((w) => !_allowed.contains(w.toLowerCase()));
          if (unknown.isNotEmpty) bad.add('${f.path}:${i + 1}: $s (${unknown.join(', ')})');
        }
      }
    }
    expect(bad, isEmpty);
  });

  // ---------------------------------------------------------------- BUG-26: text that arrives from the server
  group('sync review and rejected-unit screens with sample server payloads', () {
    setUpAll(loadAppFonts);
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    /// Every visible Text with an English word outside the allow-list (data values are Burmese here).
    List<String> english(WidgetTester tester) {
      final word = RegExp(r'[A-Za-z]{2,}');
      return {
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if ((t.data ?? t.textSpan?.toPlainText() ?? '') case final s
              when word.allMatches(s).any((w) => !_allowed.contains(w.group(0)!.toLowerCase())))
            s,
      }.toList();
    }

    Future<ProviderContainer> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (c, shop) = (await tester.runAsync(() => driftContainer(db, overrides: [
            syncApiProvider.overrideWithValue(FakeSyncApi()),
            connectivityProvider.overrideWithValue(const Stream<bool>.empty()),
          ])))!;
      addTearDown(c.dispose);
      final t = DateTime.utc(2026, 11, 14, 9);
      // Issues as the server writes them (English detail + structured data), an old row without data, an unknown kind.
      final issues = <(String, String, Map<String, Object?>?)>[
        ('duplicateBarcode', 'Barcode 8850000088001 is also used by: ကိုကာကိုလာ.',
            {'barcode': '8850000088001', 'productName': 'ကိုကာကိုလာ ဗူး', 'others': ['ကိုကာကိုလာ'], 'othersCount': 1}),
        ('duplicateBarcode', 'Barcode 1 is also used by: x.', null),
        ('duplicateSerial', 'Serial 359000000000011 is already in stock (ဖုန်း A). Both rows were kept.',
            {'serial': '359000000000011', 'productName': 'ဖုန်း B', 'others': ['ဖုန်း A', 'ဖုန်း C'], 'othersCount': 7}),
        ('serialDoubleSold', 'Serial 359 sold twice: sale line a and b. Both sales were kept.',
            {'serial': '359000000000022', 'productName': 'ဖုန်း A'}),
        ('negativeStock', 'ဆန်: stock is -2 after this sync. The sale was kept.', {'productName': 'ဆန်', 'stockMilli': -2500}),
        ('creditLimitExceeded', 'မမ owes 60,000 Ks, over the 50,000 Ks limit.',
            {'customerName': 'မမ', 'balance': 60000, 'limit': 50000}),
        ('clockSkew', 'Device clock is 12 min ahead of the server; edit times were clamped.',
            {'minutesAhead': 12, 'clampMinutes': 5}),
        ('totalMismatch', 'Sale A-0001: total: client 900, server 1000', {'receiptNo': 'A-0001', 'serverTotal': 1000}),
        ('duplicateReceiptNo', 'Receipt A-0001 already exists. Stored as A-0001*2.', {'receiptNo': 'A-0001', 'storedAs': 'A-0001*2'}),
        ('somethingNew', 'A future issue the app does not know.', {'whatever': 'English value'}),
      ];
      // Rejected units: every code, an unknown code, an old server (reason only), a setFeatures unit.
      final rejects = <(String, Map<String, Object?>, String, String?, Map<String, String>?)>[
        ('upsertProduct', {'products': [{'name': 'ဆပ်ပြာ'}]}, 'products.name is longer than 120 characters.', 'fieldTooLong',
            {'field': 'products.name', 'max': '120'}),
        ('setFeatures', {'tenantFeatures': [{'featureKey': 'expiryBatch'}, {'featureKey': 'tables'}]},
            'tenantFeatures.featureKey must not be empty.', 'fieldEmpty', {'field': 'tenantFeatures.featureKey'}),
        ('restock', <String, Object?>{}, 'stockMovements.productId 0193 does not exist in this shop.', 'notFound',
            {'field': 'stockMovements.productId'}),
        ('teleport', <String, Object?>{}, "Unknown unit kind 'teleport'.", 'unknownKind', {'kind': 'teleport'}),
        ('checkout', <String, Object?>{}, 'The database refused the unit: FK_Sales_Customer', 'databaseRefused', null),
        ('upsertCustomer', {'customers': [{'name': 'မမ'}]}, 'customers.phone must be ASCII (digits/latin letters).',
            'fieldNotAscii', {'field': 'customers.phone'}),
        ('payDebt', <String, Object?>{}, 'debtEntries.amount must be >= 1.', 'fieldTooSmall', {'field': 'debtEntries.amount', 'min': '1'}),
        ('stockAdjust', <String, Object?>{}, 'stockMovements.qtyMilli must be <= 9.', 'fieldTooLarge', {'field': 'x.y', 'max': '9'}),
        ('upsertProduct', {'products': [{'name': 'ဆီ'}]}, 'products.category is required.', null, null),
        ('upsertProduct', {'products': [{'name': 'ငံပြာရည်'}]}, 'Something odd.', 'brandNewCode', {'field': 'products.secretColumn'}),
      ];
      await tester.runAsync(() async {
        for (final (i, (kind, detail, data)) in issues.indexed) {
          await db.into(db.syncIssues).insert(SyncIssuesCompanion.insert(
                id: 'issue-$i', tenantId: shop.tenantId, kind: kind, entityTable: 'Products', entityId: 'e$i',
                detail: detail, data: Value(data == null ? null : jsonEncode(data)),
                createdAt: t.add(Duration(minutes: i)), updatedAt: t.add(Duration(minutes: i)),
              ));
        }
        for (final (i, (kind, rows, reason, code, data)) in rejects.indexed) {
          await db.into(db.outbox).insert(OutboxCompanion.insert(
                unitId: 'unit-$i', kind: kind, rowsJson: jsonEncode(rows), clientTime: t.millisecondsSinceEpoch,
                status: const Value(OutboxStatus.rejected), rejectReason: Value(reason), rejectCode: Value(code),
                rejectData: Value(data == null ? null : jsonEncode(data)),
              ));
        }
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await settle(tester);
      return c;
    }

    testWidgets('"စစ်ရန်" list: issues and rejected units are Burmese, built from the structured fields', (tester) async {
      final c = await boot(tester);
      c.read(appRouterProvider).go(Routes.syncReview);
      await settle(tester);
      expect(english(tester), isEmpty);
      // Built from data, not from the English detail:
      expect(find.textContaining('Barcode 8850000088001 ကို “ကိုကာကိုလာ ဗူး” နဲ့ “ကိုကာကိုလာ”'), findsOneWidget);
      expect(find.textContaining('“ဖုန်း A”၊ “ဖုန်း C” နဲ့ အခြား ၅ မျိုး'), findsOneWidget);
      expect(find.textContaining('Stock က -၂.၅'), findsOneWidget);
      expect(find.textContaining('အကြွေး 60,000 Ks'), findsOneWidget);
      expect(find.textContaining('ဆာဗာက ဒီစာရင်းကို စစ်ဖို့ အကြောင်းကြားထားပါတယ်'), findsOneWidget, reason: 'unknown kind');
      expect(find.textContaining('“အမည်” က စာလုံး ၁၂၀ လုံးထက် ရှည်နေပါတယ်'), findsOneWidget);
      expect(find.textContaining('လုပ်ဆောင်ချက် ပြောင်း · သက်တမ်းကုန်ရက် / Batch'), findsOneWidget, reason: 'unknown key "tables" dropped');
      expect(find.textContaining('ဆာဗာက ဒီစာရင်းကို လက်မခံပါ'), findsNWidgets(3), reason: 'old server, unknown code, databaseRefused');
    });

    testWidgets('each rejected-unit screen: no English, no internal names', (tester) async {
      final c = await boot(tester);
      final seqs = (await tester.runAsync(() => db.select(db.outbox).get()))!.map((o) => o.seq).toList();
      for (final seq in seqs) {
        c.read(appRouterProvider).go(Routes.rejectedUnit(seq));
        await settle(tester);
        expect(english(tester), isEmpty, reason: 'unit seq $seq');
        expect(find.textContaining('secretColumn'), findsNothing);
      }
    });
  });
}
