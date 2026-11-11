import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/session.dart';
import '../../../core/utils/qty.dart';
import '../data/sales_providers.dart';
import '../domain/sale.dart';

class SaleReceiptScreen extends ConsumerWidget {
  const SaleReceiptScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleByIdProvider(id));
    final shop = ref.watch(sessionProvider).shopName;
    if (sale == null) return const Scaffold();
    final pad = MediaQuery.paddingOf(context);
    final date = mmReceiptDate(sale.createdAt);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: pad.top),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const AppIcon(AppIcons.check, size: 38, color: AppColors.surface, strokeWidth: 2.6),
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        header: true,
                        child: Text('ရောင်းပြီးပါပြီ', style: AppText.s(22, weight: AppText.w700)),
                      ),
                      if (sale.pending) ...[
                        const SizedBox(height: 10),
                        Text('Offline သိမ်းထားသည် · လိုင်းရရင် sync လုပ်ပါမယ်',
                            textAlign: TextAlign.center, style: AppText.s(14, color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: DashedBox(
                    color: AppColors.inputBorder,
                    strokeWidth: 1,
                    radius: 18,
                    background: AppColors.surface,
                    padding: const EdgeInsets.all(20),
                    child: _ReceiptBody(sale: sale, shop: shop, date: date),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: 'Viber ပို့မယ်',
                          variant: ButtonVariant.outline,
                          icon: AppIcons.send,
                          height: 50,
                          radius: 14,
                          fontSize: 14,
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: 'ပုံ သိမ်းမယ်',
                          variant: ButtonVariant.outline,
                          icon: AppIcons.image,
                          height: 50,
                          radius: 14,
                          fontSize: 14,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + pad.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryButton(label: 'နောက်တစ်ခု ရောင်းမယ်', onPressed: () => context.go(Routes.pos)),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: 'ပင်မသို့',
                  variant: ButtonVariant.text,
                  height: 48,
                  fontSize: 15,
                  fontWeight: AppText.w600,
                  onPressed: () => context.go(Routes.dashboard),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.sale, required this.shop, required this.date});

  final Sale sale;
  final String shop;
  final String date;

  @override
  Widget build(BuildContext context) {
    Widget divider() => Container(height: 1, color: AppColors.border);
    Widget gap() => const SizedBox(height: 10);
    Widget small(String l, String r) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l, style: AppText.s(13, color: AppColors.textSecondary)),
            Text(r, style: AppText.s(13, color: AppColors.textSecondary)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(shop, textAlign: TextAlign.center, style: AppText.s(16, weight: AppText.w700)),
        Text('ပြေစာ #${receiptNo(sale.no)} · $date', textAlign: TextAlign.center, style: AppText.s(12, color: AppColors.muted)),
        gap(),
        divider(),
        for (final l in sale.lines) ...[
          gap(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('${l.name} × ${Qty.format(l.qtyMilli)}', style: AppText.s(14))),
              const SizedBox(width: 12),
              Text(formatMoney(l.total), style: AppText.s(14, weight: AppText.w600)),
            ],
          ),
        ],
        gap(),
        divider(),
        gap(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('စုစုပေါင်း', style: AppText.s(17, weight: AppText.w700)),
            MoneyText(sale.total, size: 17),
          ],
        ),
        if (sale.method == PaymentMethod.cash && sale.received != null) ...[
          gap(),
          small('ငွေသား လက်ခံ', formatMoney(sale.received!)),
          gap(),
          small('ပြန်အမ်း', formatMoney(sale.change! < 0 ? 0 : sale.change!)),
        ],
        const SizedBox(height: 14),
        Text('ကျေးဇူးတင်ပါတယ်', textAlign: TextAlign.center, style: AppText.s(12, color: AppColors.muted)),
      ],
    );
  }
}
