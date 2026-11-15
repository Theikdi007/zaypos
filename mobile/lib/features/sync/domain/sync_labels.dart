import 'dart:convert';

import '../../../core/sync/wire.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/utils/qty.dart';

/// Feature key (tenantFeatures.featureKey) → its Settings name. Unknown keys → null (not shown).
String? featureLabel(String key) => switch (key) {
      'quickSale' => 'အမြန်ရောင်း',
      'stock' => 'Stock မှတ်ခြင်း',
      'presetCatalog' => 'ကြိုတင်ပစ္စည်းစာရင်း',
      'expiryBatch' => 'သက်တမ်းကုန်ရက် / Batch',
      'serialWarranty' => 'IMEI / စီးရီးနံပါတ် + အာမခံ',
      'variants' => 'အရွယ်အစား / အရောင်',
      'decimalQty' => 'ဒသမ အရေအတွက်',
      'quotation' => 'ဈေးနှုန်းတင်ပြချက်',
      'serviceItems' => 'ဝန်ဆောင်မှုများ',
      _ => null,
    };

/// A JSON object string (SyncIssues.data / outbox.rejectData) → map; anything else → empty.
Map<String, dynamic> decodeFields(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final v = jsonDecode(json);
    return v is Map ? v.cast<String, dynamic>() : const {};
  } on FormatException {
    return const {};
  }
}

String? _str(Map<String, dynamic> d, String k) => switch (d[k]) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };
int? _int(Map<String, dynamic> d, String k) => switch (d[k]) {
      final num n => n.toInt(),
      final String s => int.tryParse(s),
      _ => null,
    };
String _quoted(String name) => '“$name”';

/// "“A”၊ “B” နဲ့ အခြား ၃ မျိုး" from data.others / othersCount.
String? _others(Map<String, dynamic> d) {
  final names = [for (final n in (d['others'] as List? ?? const [])) if (n is String && n.trim().isNotEmpty) _quoted(n.trim())];
  if (names.isEmpty) return null;
  final more = (_int(d, 'othersCount') ?? names.length) - names.length;
  return more > 0 ? '${names.join('၊ ')} နဲ့ အခြား ${mmDigits(more)} မျိုး' : names.join('၊ ');
}

/// BUG-26: the Burmese message of a sync issue, built from its kind + structured fields (never the
/// server's English detail). Missing fields → a shorter sentence; unknown kind → a generic message.
String issueMessage(String kind, String? dataJson) {
  final d = decodeFields(dataJson);
  final product = _str(d, 'productName')?.let(_quoted);
  final others = _others(d);
  switch (kind) {
    case 'duplicateBarcode':
      final code = _str(d, 'barcode');
      return [
        if (code != null) 'Barcode $code ကို' else 'ဒီ Barcode ကို',
        if (product != null && others != null) '$product နဲ့ $others' else ?(product ?? others),
        'ပစ္စည်းတွေမှာ သုံးထားပါတယ်။ ရောင်းတဲ့အခါ ဘယ်ပစ္စည်းလဲ ရွေးခိုင်းပါမယ်။',
      ].join(' ');
    case 'duplicateSerial':
      final serial = _str(d, 'serial');
      return [
        if (serial != null) 'IMEI $serial' else 'ဒီ IMEI',
        if (product != null) '($product)',
        if (others != null) 'က $others မှာလည်း stock ထဲ ရှိနေပါတယ်။' else 'က stock ထဲ နှစ်ခါ ရှိနေပါတယ်။',
        'နှစ်ခုလုံး သိမ်းထားပါတယ် — တစ်ခုကို စစ်ပြီး ပြင်ပါ။',
      ].join(' ');
    case 'serialDoubleSold':
      final serial = _str(d, 'serial');
      return [
        if (serial != null) 'IMEI $serial' else 'ဒီ IMEI',
        if (product != null) '($product)',
        'ကို ဖုန်းနှစ်လုံးက ရောင်းလိုက်ပါတယ်။ ရောင်းချမှု နှစ်ခုလုံး သိမ်းထားပါတယ်။',
      ].join(' ');
    case 'negativeStock':
      final stock = _int(d, 'stockMilli');
      return [
        product ?? 'ပစ္စည်းတစ်ခု',
        if (stock != null) 'ရဲ့ Stock က ${mmDigits(Qty.format(stock))} ဖြစ်နေပါတယ်။' else 'ရဲ့ Stock အနုတ် ဖြစ်နေပါတယ်။',
        'ရောင်းချမှုကို သိမ်းထားပါတယ် — Stock ကို စစ်ပြီး ပြင်ပါ။',
      ].join(' ');
    case 'creditLimitExceeded':
      final customer = _str(d, 'customerName')?.let(_quoted) ?? 'ဖောက်သည်တစ်ဦး';
      final balance = _int(d, 'balance'), limit = _int(d, 'limit');
      return balance != null && limit != null
          ? '$customer ရဲ့ အကြွေး ${formatKs(balance)} ဖြစ်နေပြီး ကန့်သတ်ချက် ${formatKs(limit)} ကို ကျော်နေပါတယ်။'
          : '$customer ရဲ့ အကြွေးက ကန့်သတ်ချက်ကို ကျော်နေပါတယ်။';
    case 'clockSkew':
      final ahead = _int(d, 'minutesAhead');
      return [
        if (ahead != null) 'ဒီဖုန်းရဲ့ နာရီက ${mmDigits(ahead)} မိနစ် စောနေပါတယ်။' else 'ဒီဖုန်းရဲ့ နာရီ မှန်မနေပါ။',
        'ဖုန်း ဆက်တင်မှာ အချိန်ကို အလိုအလျောက် ထားပါ။',
      ].join(' ');
    case 'totalMismatch':
      final no = _str(d, 'receiptNo');
      final server = _int(d, 'serverTotal');
      return [
        if (no != null) 'ပြေစာ $no ရဲ့' else 'ပြေစာတစ်ခုရဲ့',
        'စုစုပေါင်း မကိုက်ပါ။',
        if (server != null) 'ဆာဗာက ${formatKs(server)} လို့ တွက်ထားပါတယ်။',
      ].join(' ');
    case 'duplicateReceiptNo':
      final no = _str(d, 'receiptNo'), stored = _str(d, 'storedAs');
      return no != null && stored != null
          ? 'ပြေစာနံပါတ် $no ရှိပြီးသားမို့ $stored အဖြစ် သိမ်းထားပါတယ်။'
          : 'ပြေစာနံပါတ် ထပ်နေလို့ နံပါတ်အသစ်နဲ့ သိမ်းထားပါတယ်။';
    default:
      return 'ဆာဗာက ဒီစာရင်းကို စစ်ဖို့ အကြောင်းကြားထားပါတယ်။';
  }
}

/// How a resolved issue was closed: by the server because the cause is gone (data.resolution "fixed"),
/// otherwise by the owner.
String issueResolutionLabel(String? dataJson) =>
    decodeFields(dataJson)['resolution'] == 'fixed' ? 'ပြင်ပြီးသွားပါပြီ' : 'စစ်ပြီးပြီ';

/// Wire field "table.column" → a Burmese label; unknown → null.
String? _wireFieldLabel(String? field) {
  if (field == null) return null;
  final column = field.contains('.') ? field.substring(field.lastIndexOf('.') + 1) : field;
  final label = fieldLabel(column);
  return label == _unknownField ? null : label;
}

/// BUG-26: the Burmese message of a rejected unit, from the server's code + fields. Unknown code → generic.
String rejectMessage(String? code, String? dataJson) {
  final d = decodeFields(dataJson);
  final label = _wireFieldLabel(_str(d, 'field'));
  final what = label != null ? '“$label”' : 'အချက်အလက်တစ်ခု';
  final max = _int(d, 'max'), min = _int(d, 'min');
  return switch (code) {
    'fieldRequired' || 'fieldEmpty' => '$what ထည့်ရန် လိုပါတယ်။',
    'fieldTooLong' => max != null ? '$what က စာလုံး ${mmDigits(max)} လုံးထက် ရှည်နေပါတယ်။' : '$what က ရှည်လွန်းနေပါတယ်။',
    'fieldNotAscii' => '$what မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်လို့ရပါတယ်။',
    'fieldTooSmall' => min != null ? '$what က ${mmDigits(min)} ထက် ငယ်နေပါတယ်။' : '$what က ငယ်လွန်းနေပါတယ်။',
    'fieldTooLarge' => max != null ? '$what က ${mmDigits(max)} ထက် ကြီးနေပါတယ်။' : '$what က ကြီးလွန်းနေပါတယ်။',
    'notFound' => 'ဒီစာရင်းထဲက ပစ္စည်း (သို့) ဖောက်သည် တစ်ခုကို ဆာဗာမှာ ရှာမတွေ့ပါ။',
    'unknownKind' => 'ဒီစာရင်း အမျိုးအစားကို ဆာဗာက မသိသေးပါ။ အက်ပ်ကို အပ်ဒိတ်လုပ်ပါ။',
    _ => 'ဆာဗာက ဒီစာရင်းကို လက်မခံပါ။ အကူအညီဌာနကို ပို့ပေးပါ။',
  };
}

/// Server unit kind → what the owner did, in Burmese.
String unitKindLabel(String kind) => switch (kind) {
      'checkout' => 'ရောင်းချမှု',
      'voidSale' => 'ပြေစာ ပယ်ဖျက်',
      'payDebt' => 'အကြွေးဆပ်',
      'upsertProduct' => 'ပစ္စည်းအသစ်',
      'upsertCustomer' => 'ဖောက်သည်အသစ်',
      'setFeatures' => 'လုပ်ဆောင်ချက် ပြောင်း',
      'stockAdjust' => 'Stock ပြင်',
      'restock' => 'Stock ဖြည့်',
      _ => 'စာရင်း',
    };

/// "ပစ္စည်းအသစ် · ဆပ်ပြာ", "ရောင်းချမှု · A-1033 · 3,100 Ks".
String unitSummary(String kind, Map<String, dynamic> rows) {
  Map<String, dynamic>? first(String table) {
    final list = rows[table];
    return list is List && list.isNotEmpty ? (list.first as Map).cast<String, dynamic>() : null;
  }

  final sale = first(WireTable.sales);
  final detail = switch (kind) {
    'checkout' || 'voidSale' => [
        if (sale?['no'] != null) sale!['no'],
        if (sale?['total'] is num) formatKs((sale!['total'] as num).toInt()),
      ].join(' · '),
    'payDebt' => (first(WireTable.debtEntries)?['amount'] as num?)?.let((a) => formatKs(a.toInt())) ?? '',
    'upsertProduct' => first(WireTable.products)?['name'] as String? ?? '',
    'upsertCustomer' => first(WireTable.customers)?['name'] as String? ?? '',
    'setFeatures' => [
        for (final f in (rows[WireTable.tenantFeatures] as List? ?? const []))
          if (f is Map && f['featureKey'] is String) ?featureLabel(f['featureKey'] as String),
      ].join('၊ '),
    _ => '',
  };
  return detail.isEmpty ? unitKindLabel(kind) : '${unitKindLabel(kind)} · $detail';
}

/// Server SyncIssueKind → title (README §3.4).
String issueKindLabel(String kind) => switch (kind) {
      'serialDoubleSold' => 'IMEI / စီးရီးနံပါတ် တစ်ခုကို နှစ်ခါ ရောင်းမိ',
      'negativeStock' => 'Stock အနုတ် ဖြစ်နေ',
      'duplicateBarcode' => 'Barcode တူ ပစ္စည်း ရှိနေ',
      'creditLimitExceeded' => 'အကြွေး ကန့်သတ်ချက် ကျော်',
      'clockSkew' => 'ဖုန်းနာရီ မှန်မနေ',
      'totalMismatch' => 'စုစုပေါင်း မကိုက်',
      'duplicateReceiptNo' => 'ပြေစာနံပါတ် ထပ်နေ',
      'duplicateSerial' => 'IMEI / စီးရီးနံပါတ် တူ ဖုန်း နှစ်လုံး stock ထဲ ရှိနေ',
      _ => 'စစ်ရန် ကိစ္စ',
    };

/// Field names shown on the rejected-unit editor.
String fieldLabel(String column) => switch (column) {
      'name' => 'အမည်',
      'category' => 'အမျိုးအစား',
      'unit' => 'ယူနစ်',
      'barcode' => 'Barcode',
      'phone' => 'ဖုန်း',
      'address' => 'လိပ်စာ',
      'note' => 'မှတ်ချက်',
      'size' => 'ဆိုဒ်',
      'color' => 'အရောင်',
      'batchNo' => 'Batch',
      'serial' => 'IMEI / စီးရီးနံပါတ်',
      'customerName' => 'ဖောက်သည်အမည်',
      // numbers / keys that can appear in a reject reason
      'price' => 'ရောင်းဈေး',
      'cost' => 'ဝယ်ဈေး',
      'wholesalePrice' => 'လက်ကား ဈေး',
      'amount' => 'ပမာဏ',
      'received' => 'လက်ခံငွေ',
      'qtyMilli' => 'အရေအတွက်',
      'creditLimit' => 'အကြွေး ကန့်သတ်ချက်',
      'featureKey' => 'လုပ်ဆောင်ချက်',
      _ => _unknownField,
    };

/// Wire table → what it is, in Burmese (BUG-29: never the internal name). Unknown → 'စာရင်း'.
String tableLabel(String table) => switch (table) {
      WireTable.tenants => 'ဆိုင်',
      WireTable.tenantFeatures => 'လုပ်ဆောင်ချက်',
      WireTable.devices => 'ဖုန်း',
      WireTable.products => 'ပစ္စည်း',
      WireTable.productVariants => 'ဆိုဒ် / အရောင်',
      WireTable.productBatches => 'Batch',
      WireTable.productSerials => 'IMEI',
      WireTable.customers => 'ဖောက်သည်',
      WireTable.sales => 'ပြေစာ',
      WireTable.saleLines => 'ပြေစာထဲက ပစ္စည်း',
      WireTable.payments => 'ငွေပေးချေမှု',
      WireTable.stockMovements => 'Stock အဝင်အထွက်',
      WireTable.debtEntries => 'အကြွေးစာရင်း',
      _ => 'စာရင်း',
    };

/// "ဖောက်သည် · အမည်" — a rejected unit's editable field, all Burmese.
/// When the field has the table's own name (a batch's "Batch"), it is the number: "Batch · နံပါတ်".
String rowFieldLabel(String table, String column) {
  final t = tableLabel(table), f = fieldLabel(column);
  return '$t · ${f == t ? 'နံပါတ်' : f}';
}

/// Label of a column the app has no name for (never the internal name — BUG-26).
const _unknownField = 'စာသား';

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
