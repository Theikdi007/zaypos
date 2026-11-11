import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 3-column keypad. Keys: digits, '00', '' (blank) and '⌫' (backspace).
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onKey,
    this.keys = const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '⌫'],
    this.keyHeight = 52,
    this.gap = 8,
    this.radius = 12,
    this.keyColor = AppColors.surface,
  });

  static const backspace = '⌫';
  static const pinKeys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];

  final ValueChanged<String> onKey;
  final List<String> keys;
  final double keyHeight;
  final double gap;
  final double radius;
  final Color keyColor;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var r = 0; r < keys.length; r += 3) {
      if (r > 0) rows.add(SizedBox(height: gap));
      rows.add(Row(
        children: [
          for (var c = 0; c < 3; c++) ...[
            if (c > 0) SizedBox(width: gap),
            Expanded(child: _key(keys[r + c])),
          ],
        ],
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _key(String v) {
    if (v.isEmpty) return SizedBox(height: keyHeight);
    final label = v == backspace ? 'ဖျက်ရန်' : v;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: keyColor,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () => onKey(v),
          child: SizedBox(
            height: keyHeight,
            child: Center(child: Text(v, style: AppText.s(22, weight: AppText.w600, height: 1.2))),
          ),
        ),
      ),
    );
  }
}
