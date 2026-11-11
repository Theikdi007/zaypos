import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/customer_providers.dart';
import '../domain/debt_entry.dart';
import 'pay_debt_sheet.dart';

class DebtScreen extends ConsumerWidget {
  const DebtScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(customerAccountProvider(id));
    if (c == null) return const Scaffold();
    final now = DateTime.now();
    final sub = [c.customer.phone, ?c.customer.address].where((s) => s.isNotEmpty).join(' · ');
    final lastPaid = c.lastPaymentAt;
    final lastPaidLabel = lastPaid == null
        ? null
        : daysAgo(lastPaid, now) == 0
            ? 'နောက်ဆုံးပေးချေခဲ့သည် · ယနေ့'
            : 'နောက်ဆုံးပေးချေခဲ့သည် · ${mmDigits(daysAgo(lastPaid, now))} ရက်ကြာပြီ';

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'အကြွေးစာရင်း',
            onBack: () => context.pop(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            bottomGap: 16,
            trailing: AppIconButton(icon: AppIcons.edit, size: 20, semanticLabel: 'ပြင်ဆင်ရန်', onPressed: () {}),
            bottom: [
              Row(
                children: [
                  InitialAvatar(initial: c.initial, bg: AppColors.debtAvatar, fg: AppColors.debtInk, size: 56, fontSize: 20),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: AppText.s(17, weight: AppText.w700)),
                        Text(sub, style: AppText.s(13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: AppIcons.phone,
                    size: 20,
                    circle: true,
                    color: AppColors.success,
                    background: AppColors.successBg,
                    semanticLabel: 'ဖုန်းခေါ်ရန်',
                    onPressed: () {},
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: AppColors.debtBg, borderRadius: AppRadius.cardR),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ပေးရန်ကျန်ငွေ', style: AppText.s(13, color: AppColors.debtInk)),
                    const SizedBox(height: 2),
                    MoneyText(c.balance, size: 30, color: AppColors.debt),
                    if (lastPaidLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(lastPaidLabel, style: AppText.s(12, color: AppColors.debtInk)),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'ငွေပြန်ဆပ်မယ်',
                      height: 52,
                      radius: 14,
                      fontSize: 15,
                      onPressed: () => showPayDebtSheet(context, c),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Viber သတိပေး',
                      variant: ButtonVariant.outlineDark,
                      icon: AppIcons.send,
                      height: 52,
                      radius: 14,
                      fontSize: 14,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                if (c.history.isNotEmpty) ...[
                  const SectionTitle('မှတ်တမ်း'),
                  AppCard(
                    child: DividedColumn(children: [for (final h in c.history) _EntryRow(entry: h, now: now)]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.now});
  final DebtEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // Decreases (payments, negative adjustments) show as ↓ green.
    final pay = entry.effect < 0;
    final fg = pay ? AppColors.success : AppColors.debt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          InitialAvatar(
            initial: pay ? '↓' : '↑',
            bg: pay ? AppColors.successBg : AppColors.debtBg,
            fg: fg,
            size: 36,
            fontSize: 18,
            radius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: AppText.s(14, weight: AppText.w600)),
                Text(entryDateLabel(entry.createdAt, now), style: AppText.s(12, color: AppColors.muted)),
              ],
            ),
          ),
          Text('${pay ? '− ' : '+ '}${formatMoney(entry.effect.abs())}',
              style: AppText.s(15, weight: AppText.w700, color: fg)),
        ],
      ),
    );
  }
}
