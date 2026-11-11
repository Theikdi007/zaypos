import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/sale.dart';
import '../sale_ui.dart';

/// Sale list row. [detailed] adds the method dot + void/pending tags
/// (Sales History); the dashboard uses the plain variant.
class SaleRow extends StatelessWidget {
  const SaleRow({super.key, required this.sale, this.detailed = false, this.onTap});

  final Sale sale;
  final bool detailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor = sale.voided
        ? AppColors.textDisabled
        : sale.method == PaymentMethod.debt
            ? AppColors.debt
            : AppColors.text;
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: detailed ? 14 : 16, vertical: 12),
      child: Row(
        children: [
          if (detailed) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: sale.method.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sale.title, style: AppText.s(14, weight: AppText.w600)),
                Text(sale.subtitle, style: AppText.s(12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(sale.total, showUnit: false, color: amountColor, strike: sale.voided),
              if (detailed && sale.voided)
                Text('ပယ်ဖျက်ပြီး', style: AppText.s(11, weight: AppText.w700, color: AppColors.danger)),
              if (detailed && sale.pending && !sale.voided)
                Text('sync မလုပ်ရသေး', style: AppText.s(11, weight: AppText.w700, color: AppColors.debtInk)),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
