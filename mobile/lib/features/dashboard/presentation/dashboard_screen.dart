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
import '../../../core/sync/sync_providers.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/stat_card.dart';
import '../../auth/data/session.dart';
import '../../customers/data/customer_providers.dart';
import '../../products/data/product_providers.dart';
import '../../products/presentation/products_screen.dart' show ProductFilter, productMatches;
import '../../sales/data/sales_providers.dart';
import '../../sales/presentation/widgets/sale_row.dart';
import '../../sync/presentation/sync_chip.dart';
import '../domain/today_summary.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/utils/async_combine.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final todayA = ref.watch(todaySummaryProvider);
    final features = ref.watch(tenantFeaturesProvider);
    final accountsA = ref.watch(customerAccountsProvider);
    final productsA = ref.watch(productsProvider);
    final salesA = ref.watch(salesProvider);
    final ready = allReady([todayA, accountsA, productsA, salesA]);
    if (!ready.hasValue) return AsyncView(value: ready, data: (_) => const SizedBox());
    final today = todayA.requireValue;
    final accounts = accountsA.requireValue;
    final products = productsA.requireValue;
    final recent = salesA.requireValue.take(3).toList();

    final debtors = accounts.where((a) => a.hasDebt);
    final debtTotal = debtors.fold(0, (a, c) => a + c.balance);
    // Same predicate as the Products "Stock နည်း" filter (untracked excluded).
    final lowCount = products.where((p) => productMatches(ProductFilter.low, p)).length;
    final noPriceCount = products.where((p) => p.needsPrice).length;

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
        child: RefreshIndicator(
          onRefresh: () => ref.read(syncEngineProvider).syncNow(manual: true),
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                  const SyncChip(),
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
            if (noPriceCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _NeedsPriceCard(count: noPriceCount),
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
      ),
    );
  }
}

/// "ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း n ခု" → Products filtered to them.
class _NeedsPriceCard extends StatelessWidget {
  const _NeedsPriceCard({required this.count});
  final int count;

  static String label(int n) => 'ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း ${mmDigits(n)} ခု';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.debtBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.debtBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(Routes.productsNeedingPrice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label(count), style: AppText.s(14, weight: AppText.w700, color: AppColors.debtInk)),
                      const SizedBox(height: 2),
                      Text('ဈေးနှုန်း မထည့်ရင် ရောင်းတဲ့အခါ မေးပါမယ်',
                          style: AppText.s(12, color: AppColors.debtInk)),
                    ],
                  ),
                ),
                const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.debtInk),
              ],
            ),
          ),
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
