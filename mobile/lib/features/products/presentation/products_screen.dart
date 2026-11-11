import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../data/product_providers.dart';
import '../domain/product_view.dart';

enum _StockFilter { all, low, out }

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  _StockFilter _filter = _StockFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(tenantFeaturesProvider);
    final all = ref.watch(productsProvider);
    final lowCount = all.where((p) => p.isLow).length;
    final filter = features.stock ? _filter : _StockFilter.all;
    final rows = all
        .where((p) => switch (filter) {
              _StockFilter.all => true,
              _StockFilter.low => p.isLow,
              _StockFilter.out => p.isOut,
            })
        .where((p) => _query.isEmpty || p.name.contains(_query))
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
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text('ကုန်ပစ္စည်း', style: AppText.s(22, weight: AppText.w700)),
                        ),
                      ),
                      Text('စုစုပေါင်း ${all.length} မျိုး', style: AppText.s(13, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SearchField(
                    hint: 'အမည် သို့မဟုတ် barcode',
                    semanticLabel: 'ပစ္စည်းရှာရန်',
                    onChanged: (q) => setState(() => _query = q.trim()),
                  ),
                  if (features.stock) ...[
                    const SizedBox(height: 12),
                    FilterChips<_StockFilter>(
                      options: [
                        (_StockFilter.all, 'အားလုံး'),
                        (_StockFilter.low, 'Stock နည်း ($lowCount)'),
                        (_StockFilter.out, 'ကုန်သွားပြီ'),
                      ],
                      selected: filter,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ],
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
                        for (final p in rows) _ProductRow(product: p, showStock: features.stock),
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
          child: AppFab(label: 'အသစ်ထည့်မယ်', onPressed: () => context.push(Routes.addProduct)),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.showStock});

  final ProductView product;
  final bool showStock;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final (label, bg, fg) = p.isOut
        ? ('ကုန်', AppColors.dangerBg, AppColors.danger)
        : p.isLow
            ? ('${Qty.format(p.stockMilli)} ခု', AppColors.debtAvatarSoft, AppColors.debtInk)
            : ('${Qty.format(p.stockMilli)} ခု', AppColors.successBg, AppColors.success);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          InitialAvatar(initial: p.initial, bg: Color(p.tint), fg: AppColors.textStrong, size: 44, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: AppText.s(14, weight: AppText.w600)),
                Text('ဝယ်ဈေး ${formatMoney(p.cost)} · ရောင်းဈေး ${formatMoney(p.price)}',
                    style: AppText.s(12, color: AppColors.muted)),
              ],
            ),
          ),
          if (showStock) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chipR),
              child: Text(label, style: AppText.s(12, weight: AppText.w700, color: fg)),
            ),
          ],
        ],
      ),
    );
  }
}
