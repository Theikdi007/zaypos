import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Gray track with equal-width segments; selected segment is white.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment((T, String) o) {
    final on = o.$1 == selected;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? AppColors.surface : AppColors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(o.$1),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                o.$2,
                style: AppText.s(14,
                    weight: AppText.w700, color: on ? AppColors.text : AppColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
