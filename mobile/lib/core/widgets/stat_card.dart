import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// White card with a small label, a big value and an optional caption.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.valueColor = AppColors.text,
    this.valueSize = 20,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  /// Makes the card a button (ink ripple, button semantics).
  final VoidCallback? onTap;

  final String label;
  final String value;
  final String? caption;
  final Color valueColor;
  final double valueSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.s(12, color: AppColors.muted)),
          if (caption != null) const SizedBox(height: 2),
          Text(value, style: AppText.s(valueSize, weight: AppText.w700, color: valueColor)),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: AppText.s(12, color: AppColors.muted)),
          ],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardR),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
