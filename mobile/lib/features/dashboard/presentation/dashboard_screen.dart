import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/offline_sync_chip.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/stat_card.dart';
import '../../auth/data/session.dart';
import '../../customers/data/customer_providers.dart';
import '../../products/data/product_providers.dart';
import '../../sales/data/sales_providers.dart';
import '../../sales/presentation/widgets/sale_row.dart';
import '../domain/today_summary.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final today = ref.watch(todaySummaryProvider);
    final features = ref.watch(tenantFeaturesProvider);
    final accounts = ref.watch(customerAccountsProvider);
    final products = ref.watch(productsProvider);
    final recent = ref.watch(salesProvider).take(3).toList();

    final debtors = accounts.where((a) => a.hasDebt);
    final debtTotal = debtors.fold(0, (a, c) => a + c.balance);
    final lowCount = products.where((p) => p.isLow || p.isOut).length;

    final debtCard = StatCard(
      label: 'အကြွေးရရန်',
      value: formatMoney(debtTotal),
      valueColor: AppColors.debt,
      caption: 'ဖောက်သည် ${debtors.length} ဦး',
    );

    return ColoredBox(
      color: AppColors.ground,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('မင်္ဂလာပါ', style: AppText.s(13, color: AppColors.muted)),
                        Text(session.shopName, style: AppText.s(19, weight: AppText.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (today.pendingSync > 0)
                    OfflineSyncChip(label: 'Offline · sync ${mmDigits(today.pendingSync)} ခုစောင့်'),
                  AppIconButton(
                    icon: AppIcons.settings,
                    semanticLabel: 'Settings',
                    onPressed: () => context.push(Routes.settingsFeatures),
                  ),
                ],
              ),
            ),
            _Hero(today: today),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: features.stock
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: debtCard),
                        const SizedBox(width: AppSpacing.gap),
                        Expanded(
                          child: StatCard(
                            label: 'Stock နည်းနေသည်',
                            value: '$lowCount မျိုး',
                            caption: 'မှာရန်လိုသည်',
                          ),
                        ),
                      ],
                    )
                  : debtCard,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: PrimaryButton(
                label: 'ရောင်းမယ်',
                variant: ButtonVariant.dark,
                icon: AppIcons.plus,
                iconSize: 22,
                iconStroke: 2.2,
                onPressed: () => context.push(Routes.pos),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('နောက်ဆုံး အရောင်းများ', style: AppText.s(15, weight: AppText.w700)),
                  InkWell(
                    onTap: () => context.push(Routes.sales),
                    child: Text('အားလုံးကြည့်ရန်',
                        style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            AppCard(
              child: DividedColumn(children: [for (final s in recent) SaleRow(sale: s)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.today});
  final TodaySummary today;

  @override
  Widget build(BuildContext context) {
    final sign = today.changePct >= 0 ? '+' : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.cardLg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ဒီနေ့ ရောင်းရငွေ',
              style: AppText.s(13, color: AppColors.surface.withValues(alpha: 0.9))),
          const SizedBox(height: 4),
          MoneyText(today.sales,
              size: 32, color: AppColors.surface, letterSpacing: -0.5, unitSize: 16),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('အရောင်း', '${today.count} ကြိမ်'),
              const SizedBox(width: 20),
              _metric('အမြတ်', formatKs(today.profit)),
              const SizedBox(width: 20),
              _metric('မနေ့က', '$sign${today.changePct}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.s(13, color: AppColors.surface.withValues(alpha: 0.85))),
          Text(value, style: AppText.s(15, weight: AppText.w700, color: AppColors.surface)),
        ],
      );
}
