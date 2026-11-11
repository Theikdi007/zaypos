import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_icons.dart';

enum ButtonVariant {
  /// Accent fill, white text.
  primary,

  /// Dark (#111827) fill, white text.
  dark,

  /// White with 1.5px dark border.
  outlineDark,

  /// White with 1.5px light border (#D1D5DB / #E5E7EB).
  outline,

  /// White with 1.5px danger border, danger text.
  outlineDanger,

  /// Soft accent bg with accent border (e.g. "+ ခြင်းထဲထည့်မယ်").
  soft,

  /// No background, accent text.
  text,
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.height = AppSizes.primaryButton,
    this.radius = 16,
    this.fontSize = 16,
    this.icon,
    this.iconSize = 18,
    this.iconStroke = 2,
    this.trailingIcon,
    this.borderColor,
    this.borderWidth = 1.5,
    this.fontWeight = AppText.w700,
    this.horizontalPadding = 12,
    this.dimWhenDisabled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final double height;
  final double radius;
  final double fontSize;
  final String? icon;
  final double iconSize;
  final double iconStroke;
  final String? trailingIcon;
  final Color? borderColor;
  final double borderWidth;
  final FontWeight fontWeight;
  final double horizontalPadding;

  /// Render at 50% opacity when [onPressed] is null.
  final bool dimWhenDisabled;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (variant) {
      ButtonVariant.primary => (AppColors.primary, AppColors.surface, null),
      ButtonVariant.dark => (AppColors.text, AppColors.surface, null),
      ButtonVariant.outlineDark => (
        AppColors.surface,
        AppColors.text,
        AppColors.text,
      ),
      ButtonVariant.outline => (
        AppColors.surface,
        AppColors.text,
        AppColors.border,
      ),
      ButtonVariant.outlineDanger => (
        AppColors.surface,
        AppColors.danger,
        AppColors.danger,
      ),
      ButtonVariant.soft => (
        AppColors.primarySoft,
        AppColors.success,
        AppColors.primary,
      ),
      ButtonVariant.text => (AppColors.transparent, AppColors.primary, null),
    };
    final b = borderColor ?? border;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: b == null
          ? BorderSide.none
          : BorderSide(color: b, width: borderWidth),
    );
    final button = SizedBox(
      height: height,
      child: Material(
        color: bg,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: LayoutBuilder(
              builder: (context, c) {
                final text = Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.s(fontSize, weight: fontWeight, color: fg),
                );
                return Row(
                  mainAxisSize: c.hasBoundedWidth
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      AppIcon(
                        icon!,
                        size: iconSize,
                        color: fg,
                        strokeWidth: iconStroke,
                      ),
                      SizedBox(width: fontSize >= 16 ? 10 : 8),
                    ],
                    if (c.hasBoundedWidth) Flexible(child: text) else text,
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 8),
                      AppIcon(
                        trailingIcon!,
                        size: iconSize,
                        color: fg,
                        strokeWidth: iconStroke,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return dimWhenDisabled && onPressed == null
        ? Opacity(opacity: 0.5, child: button)
        : button;
  }
}
