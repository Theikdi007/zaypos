import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
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

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'အရောင်းမှတ်တမ်း',
            onBack: () => context.pop(),
            trailing: SmallOutlineButton(icon: AppIcons.calendar, label: 'ယနေ့', onPressed: () {}),
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
            child: ListView(
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
        ],
      ),
    );
  }
}
