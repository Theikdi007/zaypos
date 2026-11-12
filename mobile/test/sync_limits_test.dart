import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';

import 'drift_helpers.dart';

/// The bundled copy of GET /sync/limits (same file the app ships).
SyncLimitsData bundledLimits() => SyncLimitsData.parse(File(bundledLimitsAsset).readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final limits = bundledLimits();

  group('bundled /sync/limits', () {
    test('has the server rules the forms rely on', () {
      expect(limits.text['products.name']!.maxLength, 150);
      expect(limits.text['customers.name']!.maxLength, 100);
      expect(limits.text['tenants.name']!.maxLength, 120);
      expect(limits.text['products.barcode']!.nonAscii, NonAscii.reject);
      expect(limits.text['products.barcode']!.myanmarDigitsToAscii, isTrue);
      expect(limits.text['customers.phone']!.nonAscii, NonAscii.drop);
      expect(limits.text['products.unit']!.allowEmpty, isTrue);
      expect(limits.numbers['customers.creditLimit']!.min, 0);
    });

    test('every column the rejected-unit editor offers has a rule', () {
      for (final MapEntry(key: table, value: cols) in editableColumns.entries) {
        for (final c in cols) {
          expect(limits.text.containsKey('$table.$c'), isTrue, reason: '$table.$c');
        }
      }
    });
  });

  group('checkText', () {
    test('required, empty and length (UTF-16 units, like nvarchar)', () {
      expect(limits.checkText('products.name', '', label: 'အမည်'), 'အမည် ထည့်ပါ။');
      expect(limits.checkText('products.name', null, label: 'အမည်'), 'အမည် ထည့်ပါ။');
      expect(limits.checkText('products.name', 'က' * 150, label: 'အမည်'), isNull);
      expect(limits.checkText('products.name', 'က' * 151, label: 'အမည်'), contains('၁၅၀'));
      expect(limits.checkText('products.unit', '', label: 'ယူနစ်'), isNull, reason: 'allowEmpty');
      expect(limits.checkText('customers.address', null, label: 'လိပ်စာ'), isNull, reason: 'optional');
    });

    test('ASCII-only fields: Myanmar digits are converted, Myanmar letters are refused', () {
      expect(limits.normalize('products.barcode', ' ၈၈၅၀၉၉၉ '), '8850999');
      expect(limits.checkText('products.barcode', '၈၈၅၀၉၉၉', label: 'Barcode'), isNull);
      expect(limits.checkText('products.barcode', '885ကခ', label: 'Barcode'), contains('အင်္ဂလိပ်'));
      expect(limits.checkText('productSerials.serial', '35693803564380၉', label: 'IMEI'), isNull);
    });

    test('phone: digits converted and other non-ASCII dropped, as the server stores it', () {
      expect(limits.normalize('customers.phone', '၀၉ ၇၇၇ ၁၂၃ ၄၅၆ (ဒေါ်ခင်မာ)'), '09 777 123 456 ()');
      expect(limits.checkText('customers.phone', '၀၉ ၇၇၇ ၁၂၃ ၄၅၆', label: 'ဖုန်း'), isNull);
      expect(limits.checkText('customers.phone', '0' * 21, label: 'ဖုန်း'), isNotNull);
    });

    test('a field without a rule is accepted; checkNumber honours min/max', () {
      expect(limits.checkText('nothing.here', 'x' * 9999, label: 'x'), isNull);
      expect(limits.checkNumber('customers.creditLimit', -1, label: 'ကန့်သတ်ချက်'), contains('၀'));
      expect(limits.checkNumber('customers.creditLimit', 0, label: 'ကန့်သတ်ချက်'), isNull);
      expect(limits.checkNumber('customers.creditLimit', null, label: 'ကန့်သတ်ချက်'), isNull);
    });
  });

  group('loading', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    test('without a cached copy the bundled asset is used', () async {
      final l = await loadLimits(db);
      expect(l.text['products.name']!.maxLength, 150);
    });

    test('a cached server copy wins; a broken cache falls back to the bundled one', () async {
      final custom = File(bundledLimitsAsset).readAsStringSync().replaceFirst('"maxLength": 150', '"maxLength": 99');
      await db.writeState(LimitsKeys.json, custom);
      expect((await loadLimits(db)).text['products.name']!.maxLength, 99);

      await db.writeState(LimitsKeys.json, '{not json');
      expect((await loadLimits(db)).text['products.name']!.maxLength, 150);
    });
  });
}
