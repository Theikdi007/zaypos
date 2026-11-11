import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import 'common.dart';

/// White form section card (radius 16, padding 16, optional colored border).
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.children, this.title, this.borderColor, this.gap = 12});

  final String? title;
  final List<Widget> children;
  final Color? borderColor;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (title != null) Text(title!, style: AppText.s(15, weight: AppText.w700)),
      ...children,
    ];
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]],
        ],
      ),
    );
  }
}

/// Two equal columns with a 10px gap.
class TwoCol extends StatelessWidget {
  const TwoCol(this.a, this.b, {super.key});
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
      );
}
