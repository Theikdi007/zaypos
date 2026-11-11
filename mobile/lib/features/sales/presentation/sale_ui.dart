import 'package:flutter/painting.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/myanmar.dart';
import '../domain/sale.dart';

/// Presentation-only color per payment method.
extension PaymentMethodColor on PaymentMethod {
  Color get color => switch (this) {
        PaymentMethod.cash => AppColors.payCash,
        PaymentMethod.kbz => AppColors.payKbz,
        PaymentMethod.wave => AppColors.payWave,
        PaymentMethod.debt => AppColors.payDebt,
      };
}

/// Display strings derived from a [Sale].
extension SaleLabels on Sale {
  /// "#1030 · အကြွေး (ဦးအောင်ကျော်)"
  String get title => '#${receiptNo(no)} · ${method.label}${customerName != null ? ' ($customerName)' : ''}';

  /// "3:42 PM"
  String get time => timeLabel(createdAt);

  /// "ပစ္စည်း 4 မျိုး · 3:42 PM"
  String get subtitle => 'ပစ္စည်း $itemCount မျိုး · $time';

  /// "ယနေ့" / "နို ၇"
  String dateLabel(DateTime now) => dayLabel(createdAt, now);
}
