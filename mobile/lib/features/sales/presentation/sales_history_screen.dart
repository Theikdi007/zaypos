import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../dashboard/domain/today_summary.dart';
import '../data/sales_providers.dart';
import '../domain/sale.dart';
import 'widgets/sale_row.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/utils/async_combine.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  PaymentMethod? _filter;

  @override
  Widget build(BuildContext context) {
    final todayA = ref.watch(todaySummaryProvider);
    final salesA = ref.watch(salesProvider);
    final ready = allReady([todayA, salesA]);
    if (!ready.hasValue) return Scaffold(body: AsyncView(value: ready, data: (_) => const SizedBox()));
    final today = todayA.requireValue;
    final now = DateTime.now();
    // The header date chip is "ယနေ့": list today's sales.
    final sales = salesA.requireValue
        .where((s) => daysAgo(s.createdAt, now) == 0)
        .where((s) => _filter == null || s.method == _filter)
        .toList();

    // BUG-56: after a sale the stack is receipt → sale → this list, with
    // nothing below; back then goes to ပင်မ instead of leaving the app.
    // This route's own canPop (rebuilds when the screens above it are popped).
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    void leave() => canPop ? context.pop() : context.go(Routes.dashboard);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'အရောင်းမှတ်တမ်း',
            onBack: leave,
            // The list shows today only; the date picker behind "ယနေ့" is in the beta backlog (BUG-46),
            // so it is a label, not a button.
            trailing: const _TodayLabel(),
            bottom: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${today.count} ကြိမ်', style: AppText.s(14, color: AppColors.muted)),
                  MoneyText(today.sales, size: 14),
                ],
              ),
              FilterChips<PaymentMethod?>(
                scrollable: true,
                options: [
                  (null, 'အားလုံး'),
                  for (final m in PaymentMethod.values) (m, m.label),
                ],
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(syncEngineProvider).syncNow(manual: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                children: [
                  AppCard(
                    child: DividedColumn(children: [
                      for (final s in sales)
                        SaleRow(sale: s, detailed: true, onTap: () => context.push(Routes.sale(s.id))),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// "ယနေ့" in the header: the period this list shows. Not tappable.
class _TodayLabel extends StatelessWidget {
  const _TodayLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.inputR,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(AppIcons.calendar, size: 16, color: AppColors.text),
          const SizedBox(width: 6),
          Text('ယနေ့', style: AppText.s(13, weight: AppText.w600)),
        ],
      ),
    );
  }
}
