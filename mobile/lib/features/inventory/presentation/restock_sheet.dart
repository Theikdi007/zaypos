import 'package:flutter/material.dart';

import '../../../core/widgets/qty_sheet.dart';

/// "Stock ဖြည့်မယ်": goods received for one product. Whole units, or decimals
/// when [decimal] (TenantFeatures.decimalQty: 2.5 ပေ, 0.75 ကီလို).
/// Returns the quantity (milli-units), or null if dismissed. For an
/// [untracked] product this is its first count, which starts tracking it.
Future<int?> showRestockSheet(
  BuildContext context, {
  required String productName,
  required bool untracked,
  bool decimal = false,
  String unit = 'ခု',
}) =>
    showQtySheet(
      context,
      title: 'Stock ဖြည့်မယ်',
      subtitle: untracked
          ? '$productName · Stock မမှတ်ရသေးပါ။ လက်ရှိ ရှိနေတဲ့ အရေအတွက် ထည့်လိုက်ရင် စမှတ်ပါမယ်။'
          : '$productName · ဝင်လာတဲ့ အရေအတွက် ထည့်ပါ။',
      decimal: decimal,
      unit: unit,
    );
