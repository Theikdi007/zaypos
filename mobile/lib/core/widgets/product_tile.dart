import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../utils/money_format.dart';
import '../utils/qty.dart';

/// Stock label for a product never counted in (no restock/adjustment > 0):
/// grey, never "ကုန်", excluded from low/out counts.
const untrackedStockLabel = 'Stock မမှတ်ရသေး';

/// "ဈေးနှုန်း ထည့်ရန်": a product without a selling price (price 0).
class NeedsPriceBadge extends StatelessWidget {
  const NeedsPriceBadge({super.key});

  static const label = 'ဈေးနှုန်း ထည့်ရန်';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: const BoxDecoration(color: AppColors.debtAvatarSoft, borderRadius: AppRadius.chipR),
        child: Text(label, style: AppText.s(12, weight: AppText.w700, color: AppColors.debtInk)),
      );
}

/// POS grid tile: tint block with initial, name, price, stock and qty badge.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.name,
    required this.initial,
    required this.tint,
    required this.price,
    required this.onTap,
    this.stockLabel,
    this.stockLow = false,
    this.qtyMilli = 0,
    this.needsPrice = false,
    this.image,
  });

  /// No price yet: the badge replaces the price (tapping asks for it).
  final bool needsPrice;

  /// Product photo (shown instead of the initial); null = none.
  final ImageProvider? image;

  final String name;
  final String initial;
  final Color tint;
  /// Kyats.
  final int price;
  final String? stockLabel;
  final bool stockLow;
  /// Quantity in the cart (milli-units).
  final int qtyMilli;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inCart = qtyMilli > 0;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardR,
        side: BorderSide(color: inCart ? AppColors.primary : AppColors.surface, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10), // 12 - 2px border
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 56,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: tint, borderRadius: AppRadius.inputR),
                    child: image == null
                        ? Text(initial, style: AppText.s(22, weight: AppText.w700, color: AppColors.textStrong))
                        : Image(
                            key: const ValueKey('productPhoto'),
                            image: image!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 56,
                            gaplessPlayback: true,
                            // A broken file shows the initial, never an error box.
                            errorBuilder: (_, _, _) =>
                                Text(initial, style: AppText.s(22, weight: AppText.w700, color: AppColors.textStrong)),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(name, style: AppText.s(14, weight: AppText.w600, height: 1.4)),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: needsPrice
                            ? const Align(alignment: Alignment.centerLeft, child: NeedsPriceBadge())
                            : Text(formatMoney(price), style: AppText.s(15, weight: AppText.w700)),
                      ),
                      if (stockLabel != null)
                        Text(stockLabel!,
                            style: AppText.s(11,
                                color: stockLow ? AppColors.danger : AppColors.muted)),
                    ],
                  ),
                ],
              ),
            ),
            if (inCart)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.chipR),
                  child: Text(Qty.format(qtyMilli),
                      style: AppText.s(13, weight: AppText.w700, color: AppColors.surface, height: 1)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
