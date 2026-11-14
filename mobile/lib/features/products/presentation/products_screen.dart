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
import '../../../core/widgets/product_tile.dart' show NeedsPriceBadge, untrackedStockLabel;
import '../../inventory/application/stock_service.dart';
import '../../inventory/presentation/restock_sheet.dart';
import '../data/product_providers.dart';
import '../domain/product_view.dart';
import '../../../core/widgets/async_view.dart';

/// Products list filters. `noPrice` = products without a selling price
/// (`/products?filter=noPrice`, from the Dashboard card). `low` uses
/// [ProductView.needsRestock], the same predicate as the Dashboard card.
/// `untracked` = stock never recorded; restocking one starts tracking it.
enum ProductFilter { all, low, out, untracked, noPrice }

/// The Products filter predicate (shared with the Dashboard count).
bool productMatches(ProductFilter f, ProductView p) => switch (f) {
  ProductFilter.all => true,
  ProductFilter.low => p.needsRestock,
  ProductFilter.out => p.isOut,
  ProductFilter.untracked => p.isUntracked,
  ProductFilter.noPrice => p.needsPrice,
};

bool _isStockFilter(ProductFilter f) =>
    f == ProductFilter.low || f == ProductFilter.out || f == ProductFilter.untracked;

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key, this.initialFilter = ProductFilter.all});

  final ProductFilter initialFilter;

  /// `?filter=` value → filter (unknown = all).
  static ProductFilter filterFromQuery(String? q) =>
      ProductFilter.values.where((f) => f.name == q).firstOrNull ?? ProductFilter.all;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  late ProductFilter _filter = widget.initialFilter;
  String _query = '';

  @override
  void didUpdateWidget(ProductsScreen old) {
    super.didUpdateWidget(old);
    // The shell keeps this screen alive: follow a new ?filter= link.
    if (old.initialFilter != widget.initialFilter) _filter = widget.initialFilter;
  }

  /// Goods received: one restock unit. For an untracked product the number is
  /// its opening count: an adjustment of (count − ledger) so stock shows
  /// exactly what was counted, even after sales made before tracking (ledger
  /// ≤ 0, so the adjustment is > 0 and starts tracking).
  Future<void> _restock(ProductView p) async {
    final qtyMilli = await showRestockSheet(context, productName: p.name, untracked: p.isUntracked);
    if (qtyMilli == null || !mounted) return;
    final stock = ref.read(stockServiceProvider);
    if (p.isUntracked) {
      await stock.adjust(productId: p.id, deltaMilli: qtyMilli - p.stockMilli, note: 'opening count');
    } else {
      await stock.restock(productId: p.id, qtyMilli: qtyMilli);
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(tenantFeaturesProvider);
    final async = ref.watch(productsProvider);
    if (!async.hasValue) return AsyncView(value: async, data: (_) => const SizedBox());
    final all = async.requireValue;
    int count(ProductFilter f) => all.where((p) => productMatches(f, p)).length;
    final lowCount = count(ProductFilter.low);
    final untrackedCount = count(ProductFilter.untracked);
    final noPriceCount = count(ProductFilter.noPrice);
    final filter = !features.stock && _isStockFilter(_filter) ? ProductFilter.all : _filter;
    final showNoPrice = noPriceCount > 0 || filter == ProductFilter.noPrice;
    final showUntracked = untrackedCount > 0 || filter == ProductFilter.untracked;
    final rows = all
        .where((p) => productMatches(filter, p))
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
                  if (features.stock || showNoPrice) ...[
                    const SizedBox(height: 12),
                    FilterChips<ProductFilter>(
                      scrollable: true,
                      options: [
                        (ProductFilter.all, 'အားလုံး'),
                        if (features.stock) (ProductFilter.low, 'Stock နည်း ($lowCount)'),
                        if (features.stock) (ProductFilter.out, 'ကုန်သွားပြီ'),
                        if (features.stock && showUntracked)
                          (ProductFilter.untracked, 'Stock မမှတ်ရသေး ($untrackedCount)'),
                        if (showNoPrice) (ProductFilter.noPrice, 'ဈေးနှုန်းမရှိ ($noPriceCount)'),
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
                      child: DividedColumn(
                        children: [
                          for (final p in rows)
                            _ProductRow(
                              product: p,
                              showStock: features.stock,
                              onRestock: features.stock ? () => _restock(p) : null,
                            ),
                        ],
                      ),
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
  const _ProductRow({required this.product, required this.showStock, this.onRestock});

  final ProductView product;
  final bool showStock;

  /// Tap = "Stock ဖြည့်မယ်" (stock feature on).
  final VoidCallback? onRestock;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final (label, bg, fg) = p.isUntracked
        ? (untrackedStockLabel, AppColors.fill, AppColors.muted)
        : p.isOut
        ? ('ကုန်', AppColors.dangerBg, AppColors.danger)
        : p.isLow
        ? ('${Qty.format(p.stockMilli)} ခု', AppColors.debtAvatarSoft, AppColors.debtInk)
        : ('${Qty.format(p.stockMilli)} ခု', AppColors.successBg, AppColors.success);
    return InkWell(
      onTap: onRestock,
      child: Padding(
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
                  if (p.needsPrice)
                    const Padding(padding: EdgeInsets.only(top: 2), child: NeedsPriceBadge())
                  else
                    Text(
                      'ဝယ်ဈေး ${formatMoney(p.cost)} · ရောင်းဈေး ${formatMoney(p.price)}',
                      style: AppText.s(12, color: AppColors.muted),
                    ),
                ],
              ),
            ),
            if (showStock) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chipR),
                child: Text(
                  label,
                  style: AppText.s(12, weight: AppText.w700, color: fg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
