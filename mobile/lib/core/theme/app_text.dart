import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography: Inter for Latin/numbers with Noto Sans Myanmar fallback,
/// line-height 1.6 as in the design. Both fonts are bundled assets
/// (see pubspec `fonts:`), so text renders with no internet.
abstract final class AppText {
  static const double lineHeight = 1.6;

  static const inter = 'Inter';
  static const myanmar = 'NotoSansMyanmar';
  static const fallback = [myanmar];

  /// Base style. Use [s] for all text in widgets.
  static TextStyle s(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: inter,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: weight,
      // Bundled fonts are variable; drive the weight axis explicitly.
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      color: color,
      height: height ?? lineHeight,
      letterSpacing: letterSpacing,
      decoration: decoration,
      decorationColor: color,
    );
  }

  static const w400 = FontWeight.w400;
  static const w600 = FontWeight.w600;
  static const w700 = FontWeight.w700;

  static TextTheme textTheme() {
    return TextTheme(
      headlineSmall: s(24, weight: w700),
      titleLarge: s(22, weight: w700),
      titleMedium: s(19, weight: w700),
      bodyLarge: s(15),
      bodyMedium: s(14),
      bodySmall: s(12, color: AppColors.muted),
      labelLarge: s(15, weight: w700),
    );
  }
}
