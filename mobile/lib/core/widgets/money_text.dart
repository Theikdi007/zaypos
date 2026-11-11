import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/money_format.dart';

/// Renders an amount like "245,800 Ks". When [unitSize] is set, the "Ks"
/// suffix is drawn smaller (hero amounts). [showUnit] = false renders "245,800".
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.size = 15,
    this.weight = AppText.w700,
    this.color = AppColors.text,
    this.showUnit = true,
    this.unitSize,
    this.unitWeight = AppText.w600,
    this.unitColor,
    this.letterSpacing,
    this.prefix = '',
    this.strike = false,
    this.textAlign,
  });

  /// Kyats.
  final int amount;
  final double size;
  final FontWeight weight;
  final Color color;
  final bool showUnit;
  final double? unitSize;
  final FontWeight unitWeight;
  final Color? unitColor;
  final double? letterSpacing;
  final String prefix;
  final bool strike;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = AppText.s(size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        decoration: strike ? TextDecoration.lineThrough : null);
    final number = '$prefix${formatMoney(amount)}';
    if (!showUnit) return Text(number, style: base, textAlign: textAlign);
    if (unitSize == null) return Text('$number Ks', style: base, textAlign: textAlign);
    return Text.rich(
      TextSpan(text: '$number ', children: [
        TextSpan(
          text: 'Ks',
          style: AppText.s(unitSize!,
              weight: unitWeight, color: unitColor ?? color, letterSpacing: 0),
        ),
      ]),
      style: base,
      textAlign: textAlign,
    );
  }
}
