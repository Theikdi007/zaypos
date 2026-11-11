import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../customers/data/customer_providers.dart';
import '../../products/data/product_providers.dart';
import '../data/sales_providers.dart';
import '../domain/sale.dart';
import 'sale_ui.dart';

class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.id});

  final String id;

  void _toggleVoid(WidgetRef ref, Sale sale) {
    final voiding = !sale.voided;
    final sign = voiding ? 1 : -1;
    ref.read(salesProvider.notifier).setVoided(sale.id, voiding);
    for (final l in sale.lines) {
      if (l.productId != null) ref.read(productsProvider.notifier).adjustStock(l.productId!, sign * l.qtyMilli);
    }
    if (sale.method == PaymentMethod.debt && sale.customerId != null) {
      // Append-only ledger: reverse (or re-apply) the credit sale.
      ref.read(debtLedgerProvider.notifier).adjustment(
            sale.customerId!,
            -sign * sale.total,
            saleId: sale.id,
            note: voiding ? 'void' : 'unvoid',
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleByIdProvider(id));
    if (sale == null) return const Scaffold();

    final (badge, badgeBg, badgeFg) = sale.voided
        ? ('ပယ်ဖျက်ပြီး', AppColors.dangerBg, AppColors.danger)
        : sale.pending
            ? ('sync မလုပ်ရသေး', AppColors.debtBg, AppColors.debtInk)
            : ('Sync ပြီး', AppColors.successBg, AppColors.success);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'အရောင်း #${sale.no}',
            onBack: () => context.pop(),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: badgeBg, borderRadius: AppRadius.chipR),
              child: Text(badge, style: AppText.s(12, weight: AppText.w700, color: badgeFg)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: _InfoGrid(sale: sale),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('ပစ္စည်း ${sale.itemCount} မျိုး', style: AppText.s(15, weight: AppText.w700)),
                      ),
                      DividedColumn(dividerOnTop: true, children: [
                        for (final l in sale.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(l.name, style: AppText.s(14, weight: AppText.w600)),
                                      Text('${Qty.format(l.qtyMilli)} × ${formatMoney(l.price)}',
                                          style: AppText.s(12, color: AppColors.muted)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                MoneyText(l.total, size: 14, showUnit: false),
                              ],
                            ),
                          ),
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('စုစုပေါင်း', style: AppText.s(17, weight: AppText.w700)),
                            MoneyText(sale.total, size: 17, strike: sale.voided),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (sale.voided)
                  AppCard(
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    color: AppColors.dangerBg,
                    radius: 14,
                    child: Text(
                      sale.customerName != null
                          ? 'ပယ်ဖျက်ပြီးပါပြီ။ Stock ပြန်ထည့်ပြီး ${sale.customerName}ရဲ့ အကြွေးထဲက ${formatKs(sale.total)} ကို နုတ်လိုက်ပါပြီ။'
                          : 'ပယ်ဖျက်ပြီးပါပြီ။',
                      style: AppText.s(13, weight: AppText.w600, color: AppColors.dangerInk),
                    ),
                  ),
              ],
            ),
          ),
          BottomActionBar(
            child: Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'ပြေစာ ပို့မယ်',
                    variant: ButtonVariant.outline,
                    height: 54,
                    radius: 14,
                    fontSize: 14,
                    icon: AppIcons.send,
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: sale.voided ? 'ပယ်ဖျက်မှု ပြန်ရုပ်' : 'ပယ်ဖျက်မယ်',
                    variant: ButtonVariant.outlineDanger,
                    height: 54,
                    radius: 14,
                    fontSize: 14,
                    onPressed: () => _toggleVoid(ref, sale),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, Widget value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label, style: AppText.s(12, color: AppColors.muted)), value],
        );
    Widget v(String t, [Color c = AppColors.text]) => Text(t, style: AppText.s(14, weight: AppText.w600, color: c));

    final cells = [
      cell('ရက်စွဲ', v('${sale.dateLabel(DateTime.now())} · ${sale.time}')),
      cell('ရောင်းသူ', v('ဆိုင်ရှင်')),
      cell('ငွေပေးချေမှု', v(sale.method.label, sale.method == PaymentMethod.debt ? AppColors.debt : AppColors.text)),
      if (sale.customerName != null)
        cell(
          'ဖောက်သည်',
          InkWell(
            onTap: sale.customerId == null ? null : () => context.push(Routes.customer(sale.customerId!)),
            child: v(sale.customerName!, AppColors.primary),
          ),
        ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cells.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}
