import '../../../core/sync/wire.dart';
import '../../../core/utils/money_format.dart';

/// Server unit kind → what the owner did, in Burmese.
String unitKindLabel(String kind) => switch (kind) {
      'checkout' => 'ရောင်းချမှု',
      'voidSale' => 'ပြေစာ ပယ်ဖျက်',
      'payDebt' => 'အကြွေးဆပ်',
      'upsertProduct' => 'ပစ္စည်းအသစ်',
      'upsertCustomer' => 'ဖောက်သည်အသစ်',
      'setFeatures' => 'Feature ပြောင်း',
      'stockAdjust' => 'Stock ပြင်',
      'restock' => 'Stock ဖြည့်',
      _ => kind,
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
    'setFeatures' => [for (final f in (rows[WireTable.tenantFeatures] as List? ?? const [])) (f as Map)['featureKey']].join(', '),
    _ => '',
  };
  return detail.isEmpty ? unitKindLabel(kind) : '${unitKindLabel(kind)} · $detail';
}

/// Server SyncIssueKind → title (README §3.4).
String issueKindLabel(String kind) => switch (kind) {
      'serialDoubleSold' => 'IMEI / Serial တစ်ခုကို နှစ်ခါ ရောင်းမိ',
      'negativeStock' => 'Stock အနုတ် ဖြစ်နေ',
      'duplicateBarcode' => 'Barcode တူ ပစ္စည်း ရှိနေ',
      'creditLimitExceeded' => 'အကြွေး ကန့်သတ်ချက် ကျော်',
      'clockSkew' => 'ဖုန်းနာရီ မှန်မနေ',
      'totalMismatch' => 'စုစုပေါင်း မကိုက်',
      'duplicateReceiptNo' => 'ပြေစာနံပါတ် ထပ်နေ',
      _ => kind,
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
      'size' => 'Size',
      'color' => 'အရောင်',
      'batchNo' => 'Batch',
      'serial' => 'IMEI / Serial',
      'customerName' => 'ဖောက်သည်အမည်',
      _ => column,
    };

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
