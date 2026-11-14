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
import '../application/customer_service.dart';
import '../data/customer_providers.dart';
import '../domain/debt_entry.dart';
import 'pay_debt_sheet.dart';
import '../../../core/widgets/async_view.dart';

class DebtScreen extends ConsumerWidget {
  const DebtScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerAccountProvider(id));
    if (!async.hasValue) return Scaffold(body: AsyncView(value: async, data: (_) => const SizedBox()));
    final c = async.requireValue;
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
                    child: DividedColumn(children: [
                      for (final h in c.history)
                        _EntryRow(
                          entry: h,
                          now: now,
                          reversed: c.isReversed(h),
                          onReverse: c.canReverse(h) ? () => _confirmReverse(context, ref, h) : null,
                        ),
                    ]),
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

/// BUG-4: a wrong payment is corrected with a reversal row, never deleted.
Future<void> _confirmReverse(BuildContext context, WidgetRef ref, DebtEntry payment) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('ငွေပြန်ဆပ် ${formatKs(payment.amount)} ကို ပြန်ပယ်မလား?', style: AppText.s(16, weight: AppText.w700)),
      content: Text(
        'မှားသွင်းမိတဲ့ ငွေပြန်ဆပ်ကို ပြင်ဖို့ပါ။ မှတ်တမ်းကို မဖျက်ပါ — ပြန်ပယ်တဲ့ စာရင်းတစ်ကြောင်း ထပ်ထည့်ပြီး '
        'ပေးရန်ကျန်ငွေ ${formatKs(payment.amount)} ပြန်တိုးပါမယ်။',
        style: AppText.s(14),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်တော့ပါ')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('ပြန်ပယ်မယ်', style: AppText.s(14, weight: AppText.w700, color: AppColors.danger)),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(customerServiceProvider).reversePayment(payment);
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.now, this.reversed = false, this.onReverse});
  final DebtEntry entry;
  final DateTime now;

  /// A payment that a later reversal row cancelled.
  final bool reversed;

  /// Tap a payment to reverse it (null = not reversible).
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    // Decreases (payments, negative adjustments) show as ↓ green.
    final pay = entry.effect < 0;
    final fg = reversed ? AppColors.muted : pay ? AppColors.success : AppColors.debt;
    final row = Padding(
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
                Text(
                  reversed
                      ? '${entryDateLabel(entry.createdAt, now)} · ပြန်ပယ်ပြီး'
                      : entryDateLabel(entry.createdAt, now),
                  style: AppText.s(12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            '${pay ? '− ' : '+ '}${formatMoney(entry.effect.abs())}',
            style: AppText.s(15, weight: AppText.w700, color: fg)
                .copyWith(decoration: reversed ? TextDecoration.lineThrough : null),
          ),
        ],
      ),
    );
    if (onReverse == null) return row;
    return Semantics(
      button: true,
      hint: 'ပြန်ပယ်ရန်',
      child: InkWell(onTap: onReverse, child: row),
    );
  }
}
