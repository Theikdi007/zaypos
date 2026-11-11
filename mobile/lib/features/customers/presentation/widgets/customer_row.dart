import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/utils/myanmar.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/customer_account.dart';

/// Customer list row: avatar, name, "phone · last activity", balance.
class CustomerRow extends StatelessWidget {
  const CustomerRow({super.key, required this.account, this.onTap});

  final CustomerAccount account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final now = DateTime.now();
    final overdue = a.isOverdue(now);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            InitialAvatar(
              initial: a.initial,
              bg: overdue ? AppColors.dangerBg : AppColors.debtAvatarSoft,
              fg: overdue ? AppColors.danger : AppColors.debtInk,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: AppText.s(14, weight: AppText.w600)),
                  Text('${a.customer.phone} · ${agoLabel(a.lastActivityAt, now)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (a.hasDebt)
                  MoneyText(a.balance, showUnit: false, color: AppColors.debt)
                else
                  Text('ရှင်းပြီး', style: AppText.s(15, weight: AppText.w700, color: AppColors.success)),
                if (overdue)
                  Text('၃၀ ရက်ကျော်', style: AppText.s(11, weight: AppText.w700, color: AppColors.danger)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
