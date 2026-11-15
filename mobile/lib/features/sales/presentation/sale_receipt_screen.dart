import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/session.dart';
import '../data/sales_providers.dart';
import 'receipt_image.dart';
import '../../../core/widgets/async_view.dart';

class SaleReceiptScreen extends ConsumerWidget {
  const SaleReceiptScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleByIdProvider(id));
    final shop = ref.watch(sessionProvider).shopName;
    if (!async.hasValue) return Scaffold(body: AsyncView(value: async, data: (_) => const SizedBox()));
    final sale = async.requireValue;
    if (sale == null) return const Scaffold();
    final pad = MediaQuery.paddingOf(context);

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
                        Text('လိုင်းမရှိဘဲ သိမ်းထားသည် · လိုင်းရရင် Sync လုပ်ပါမယ်',
                            textAlign: TextAlign.center, style: AppText.s(14, color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ReceiptCard(sale: sale, shop: shop),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) => PrimaryButton(
                            label: receiptShareText,
                            variant: ButtonVariant.outline,
                            icon: AppIcons.send,
                            height: 50,
                            radius: 14,
                            fontSize: 14,
                            onPressed: () => shareReceipt(context, ref, sale),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) => PrimaryButton(
                            label: receiptSaveText,
                            variant: ButtonVariant.outline,
                            icon: AppIcons.image,
                            height: 50,
                            radius: 14,
                            fontSize: 14,
                            onPressed: () => saveReceipt(context, ref, sale),
                          ),
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
