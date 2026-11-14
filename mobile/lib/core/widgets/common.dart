import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_icons.dart';

/// 44×44 icon button (back / close / settings).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 22,
    this.color = AppColors.text,
    this.background = AppColors.transparent,
    this.circle = false,
  });

  final String icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final Color color;
  final Color background;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(circle ? 999 : 12);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox(
            width: AppSizes.touch,
            height: AppSizes.touch,
            child: Center(child: AppIcon(icon, size: size, color: color)),
          ),
        ),
      ),
    );
  }
}

/// White top header: [leading] 44px button + 19px bold title + [trailing].
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.onBack,
    this.leadingIcon = AppIcons.back,
    this.leadingLabel = 'နောက်သို့',
    this.trailing,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 12),
    this.bottomGap = 12,
  });

  final String title;
  final VoidCallback? onBack;
  final String leadingIcon;
  final String leadingLabel;
  final Widget? trailing;
  final List<Widget>? bottom;
  final EdgeInsets padding;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: AppColors.surface,
      padding: padding.copyWith(top: padding.top + top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconButton(icon: leadingIcon, onPressed: onBack, semanticLabel: leadingLabel),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: AppText.s(19, weight: AppText.w700)),
                ),
              ),
              ?trailing,
            ],
          ),
          for (final w in bottom ?? const <Widget>[]) ...[SizedBox(height: bottomGap), w],
        ],
      ),
    );
  }
}

/// White rounded card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = AppSpacing.pagePadding,
    this.color = AppColors.surface,
    this.borderColor,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null ? null : Border.all(color: borderColor!, width: 1.5),
      ),
      child: child,
    );
  }
}

/// List row inside a card with a bottom divider (omitted on the last row).
class DividedColumn extends StatelessWidget {
  const DividedColumn({super.key, required this.children, this.dividerColor = AppColors.divider, this.dividerOnTop = false});

  final List<Widget> children;
  final Color dividerColor;

  /// Draw the divider above each row (incl. first) instead of between rows.
  final bool dividerOnTop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: dividerOnTop
                  ? Border(top: BorderSide(color: dividerColor))
                  : (i < children.length - 1
                      ? Border(bottom: BorderSide(color: dividerColor))
                      : const Border()),
            ),
            child: children[i],
          ),
      ],
    );
  }
}

/// Section title above a card ("နောက်ဆုံး အရောင်းများ").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.margin = const EdgeInsets.fromLTRB(20, 16, 20, 8), this.size = 15, this.color = AppColors.text});

  final String text;
  final EdgeInsets margin;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Text(text, style: AppText.s(size, weight: AppText.w700, color: color)),
    );
  }
}

/// Pill filter chip row (selected = dark).
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.scrollable = false,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        PillChip(
          label: options[i].$2,
          selected: options[i].$1 == selected,
          onTap: () => onChanged(options[i].$1),
        ),
      ],
    ];
    if (!scrollable) return Row(children: chips);
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips));
  }
}

class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.text : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AppColors.text : AppColors.border, width: 1.5),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(label,
                style: AppText.s(13,
                    weight: AppText.w600,
                    color: selected ? AppColors.surface : AppColors.textSecondary,
                    height: 1.2)),
          ),
        ),
      ),
    );
  }
}

/// Gray rounded search field with leading search icon.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.semanticLabel, this.onChanged});

  final String hint;
  final String semanticLabel;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const AppIcon(AppIcons.search, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: semanticLabel,
              textField: true,
              child: TextField(
                onChanged: onChanged,
                style: AppText.s(15),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: AppText.s(15, color: AppColors.muted),
                ).copyWith(filled: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bordered input box (height 48, radius 12, 1.5px #D1D5DB).
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.controller,
    this.hint,
    this.initialValue,
    this.keyboardType,
    this.onChanged,
    this.height = 48,
    this.fontSize = 15,
    this.fontWeight = AppText.w400,
    this.radius = 12,
    this.borderColor = AppColors.inputBorder,
    this.borderWidth = 1.5,
    this.obscure = false,
    this.maxLines = 1,
    this.inputFormatters,
    this.horizontalPadding = 12,
    this.prefix,
    this.semanticLabel,
    this.textAlign = TextAlign.start,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? initialValue;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;
  final double radius;
  final Color borderColor;
  final double borderWidth;
  final bool obscure;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final double horizontalPadding;
  final Widget? prefix;
  final String? semanticLabel;
  final TextAlign textAlign;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      onFieldSubmitted: onSubmitted,
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      keyboardType: keyboardType,
      onChanged: onChanged,
      obscureText: obscure,
      maxLines: maxLines,
      textAlign: textAlign,
      inputFormatters: inputFormatters,
      style: AppText.s(fontSize, weight: fontWeight),
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: AppText.s(fontSize, color: AppColors.subtle),
      ).copyWith(filled: false),
    );
    return Container(
      height: maxLines == 1 ? height : null,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: maxLines == 1 ? 0 : 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Row(
        children: [
          ?prefix,
          Expanded(child: semanticLabel == null ? field : Semantics(label: semanticLabel, child: field)),
        ],
      ),
    );
  }
}

/// Label above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false, this.size = 14, this.color = AppColors.text});

  final String text;
  final bool required;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: AppText.s(size, weight: AppText.w600, color: color));
    if (!required) return label;
    // Label and red asterisk as separate texts (the label stays findable by
    // its own text), read as one by screen readers.
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: label),
          Text(' *', style: AppText.s(size, weight: AppText.w600, color: AppColors.danger)),
        ],
      ),
    );
  }
}

/// Labeled field: label + 6px + child.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.small = false,
    this.helper,
    this.error,
  });

  final String label;
  final Widget child;
  final bool required;

  /// 13px #374151 label (inside cards) instead of 14px.
  final bool small;
  final String? helper;

  /// Validation message (red, announced); shown instead of [helper].
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label,
            required: required,
            size: small ? 13 : 14,
            color: small ? AppColors.textSecondary : AppColors.text),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Semantics(liveRegion: true, child: Text(error!, style: AppText.s(12, color: AppColors.danger))),
        ] else if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper!, style: AppText.s(12, color: AppColors.muted)),
        ],
      ],
    );
  }
}

/// Simple dropdown styled like [AppInput].
class AppSelect<T> extends StatelessWidget {
  const AppSelect({super.key, required this.items, required this.value, required this.onChanged, required this.label});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.inputR,
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: Semantics(
          label: label,
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            borderRadius: AppRadius.inputR,
            dropdownColor: AppColors.surface,
            icon: const Icon(Icons.expand_more, color: AppColors.textSecondary, size: 20),
            style: AppText.s(15),
            items: [
              for (final i in items)
                DropdownMenuItem(value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

/// White bar pinned to the bottom with top border (form/checkout actions).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + inset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
  }
}

/// Circle (or rounded square) with an initial letter.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.initial,
    required this.bg,
    required this.fg,
    this.size = 42,
    this.fontSize = 16,
    this.radius,
  });

  final String initial;
  final Color bg;
  final Color fg;
  final double size;
  final double fontSize;

  /// null = circle.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius ?? size / 2),
      ),
      child: Text(initial, style: AppText.s(fontSize, weight: AppText.w700, color: fg, height: 1.2)),
    );
  }
}

/// Extended FAB matching the design (accent, radius 18, soft shadow).
class AppFab extends StatelessWidget {
  const AppFab({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: AppColors.fabShadow, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.plus, size: 20, color: AppColors.surface, strokeWidth: 2.2),
                const SizedBox(width: 8),
                Text(label, style: AppText.s(15, weight: AppText.w700, color: AppColors.surface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 40px outlined header button with a 16px icon ("ယနေ့", "Excel").
class SmallOutlineButton extends StatelessWidget {
  const SmallOutlineButton({super.key, required this.icon, required this.label, required this.onPressed});

  final String icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.inputR,
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: AppRadius.inputR,
        onTap: onPressed,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 16, color: AppColors.text),
              const SizedBox(width: 6),
              Text(label, style: AppText.s(13, weight: AppText.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40×5 bottom-sheet grabber.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.padding = const EdgeInsets.only(top: 10, bottom: 6)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Center(
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(color: AppColors.inputBorder, borderRadius: AppRadius.chipR),
          ),
        ),
      );
}
