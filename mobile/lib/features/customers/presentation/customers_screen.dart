import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../data/customer_providers.dart';
import 'widgets/customer_row.dart';
import '../../../core/widgets/async_view.dart';

enum _Tab { debt, overdue, all }

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  _Tab _tab = _Tab.debt;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerAccountsProvider);
    if (!async.hasValue) return AsyncView(value: async, data: (_) => const SizedBox());
    final all = async.requireValue;
    final now = DateTime.now();
    final debtors = all.where((c) => c.hasDebt).toList();
    final total = debtors.fold(0, (a, c) => a + c.balance);
    final overdueCount = all.where((c) => c.isOverdue(now)).length;
    final rows = all
        .where((c) => switch (_tab) {
              _Tab.debt => c.hasDebt,
              _Tab.overdue => c.isOverdue(now),
              _Tab.all => true,
            })
        .where((c) => _query.isEmpty || c.name.contains(_query) || c.customer.phone.replaceAll(' ', '').contains(_query.replaceAll(' ', '')))
        .toList();
    final top = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.surface,
              padding: EdgeInsets.fromLTRB(20, 20 + top, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text('ဖောက်သည် · အကြွေး', style: AppText.s(22, weight: AppText.w700)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(color: AppColors.debtBg, borderRadius: AppRadius.cardR),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('စုစုပေါင်း ရရန်ကျန်', style: AppText.s(12, color: AppColors.debtInk)),
                              MoneyText(total, size: 22, color: AppColors.debt),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('အကြွေးရှိသူ', style: AppText.s(12, color: AppColors.debtInk)),
                            Text('${debtors.length} ဦး',
                                style: AppText.s(17, weight: AppText.w700, color: AppColors.debtInk)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SearchField(
                    hint: 'အမည် သို့မဟုတ် ဖုန်းနံပါတ်',
                    semanticLabel: 'ဖောက်သည်ရှာရန်',
                    onChanged: (q) => setState(() => _query = q.trim()),
                  ),
                  const SizedBox(height: 12),
                  FilterChips<_Tab>(
                    // BUG-8: scrolls sideways on narrow phones (320 px) instead of overflowing.
                    scrollable: true,
                    options: [
                      (_Tab.debt, 'အကြွေးရှိသူ'),
                      (_Tab.overdue, 'ကြာနေပြီ ($overdueCount)'),
                      (_Tab.all, 'အားလုံး'),
                    ],
                    selected: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 96),
                children: [
                  if (rows.isNotEmpty)
                    AppCard(
                      child: DividedColumn(children: [
                        for (final c in rows)
                          CustomerRow(account: c, onTap: () => context.push(Routes.customer(c.id))),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: AppSpacing.page,
          bottom: 20,
          child: AppFab(label: 'ဖောက်သည်အသစ်', onPressed: () => context.push(Routes.addCustomer)),
        ),
      ],
    );
  }
}
