import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';
import 'package:zaypos_app/core/sync/wire_decode.dart';
import 'package:zaypos_app/features/sync/domain/sync_labels.dart';

/// BUG-26: issue / reject messages are built in the app (Burmese) from the server's code + structured fields.
void main() {
  test('pull: syncIssues.data is kept as a JSON object string (string or object on the wire); missing → null', () {
    const d = WireDecoder('t1');
    Map<String, dynamic> row(Object? data) => {
          'id': 'i1', 'tenantId': 't1', 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': 'p1',
          'detail': 'Barcode 1 is also used by: A.', 'data': data,
          'createdAt': '2026-11-14T09:00:00Z', 'updatedAt': '2026-11-14T09:00:00Z',
        };
    expect(d.issue(row('{"barcode":"1"}')).data, '{"barcode":"1"}');
    expect(decodeFields(d.issue(row({'barcode': '1', 'others': ['A']})).data), {'barcode': '1', 'others': ['A']});
    expect(d.issue(row(null)).data, isNull);
  });

  test('push result: code + data are read; an old server (reason only) gives null / empty', () {
    final r = UnitResult.fromJson({
      'unitId': 'u', 'outcome': 'rejected', 'reason': 'products.name is longer than 120 characters.',
      'code': 'fieldTooLong', 'data': {'field': 'products.name', 'max': '120'},
    });
    expect(r.code, 'fieldTooLong');
    expect(r.data, {'field': 'products.name', 'max': '120'});
    final old = UnitResult.fromJson({'unitId': 'u', 'outcome': 'rejected', 'reason': 'x'});
    expect(old.code, isNull);
    expect(old.data, isEmpty);
  });

  test('issue messages use the fields and fall back without them; never the English detail', () {
    expect(issueMessage('duplicateBarcode', '{"barcode":"885","productName":"ခ","others":["က"],"othersCount":1}'),
        'Barcode 885 ကို “ခ” နဲ့ “က” ပစ္စည်းတွေမှာ သုံးထားပါတယ်။ ရောင်းတဲ့အခါ ဘယ်ပစ္စည်းလဲ ရွေးခိုင်းပါမယ်။');
    expect(issueMessage('duplicateBarcode', null), startsWith('ဒီ Barcode ကို ပစ္စည်းတွေမှာ'));
    expect(issueMessage('duplicateBarcode', 'not json'), startsWith('ဒီ Barcode ကို'));
    expect(issueMessage('negativeStock', '{"productName":"ဆန်","stockMilli":-2000}'), startsWith('“ဆန်” ရဲ့ Stock က -၂ ဖြစ်နေပါတယ်။'));
    expect(issueMessage('clockSkew', '{"minutesAhead":12}'), startsWith('ဒီဖုန်းရဲ့ နာရီက ၁၂ မိနစ်'));
    expect(issueMessage('whoKnows', '{"x":"English"}'), 'ဆာဗာက ဒီစာရင်းကို စစ်ဖို့ အကြောင်းကြားထားပါတယ်။');
    expect(issueKindLabel('whoKnows'), 'စစ်ရန် ကိစ္စ');
  });

  test('reject messages: field labels, never the wire name; unknown code / field → generic', () {
    expect(rejectMessage('fieldTooLong', '{"field":"products.name","max":"120"}'), '“အမည်” က စာလုံး ၁၂၀ လုံးထက် ရှည်နေပါတယ်။');
    expect(rejectMessage('fieldEmpty', '{"field":"tenantFeatures.featureKey"}'), 'စာသားတစ်ခု ထည့်ရန် လိုပါတယ်။');
    expect(rejectMessage('fieldTooSmall', '{"field":"debtEntries.amount","min":"1"}'), 'စာသားတစ်ခု က ၁ ထက် ငယ်နေပါတယ်။');
    expect(rejectMessage(null, null), 'ဆာဗာက ဒီစာရင်းကို လက်မခံပါ။ အကူအညီဌာနကို ပို့ပေးပါ။');
    expect(rejectMessage('brandNew', '{"field":"x.secret"}'), isNot(contains('secret')));
    expect(unitKindLabel('teleport'), 'စာရင်း');
    expect(unitSummary('setFeatures', {
      'tenantFeatures': [{'featureKey': 'variants'}, {'featureKey': 'tables'}],
    }), 'လုပ်ဆောင်ချက် ပြောင်း · အရွယ်အစား / အရောင်');
  });
}
