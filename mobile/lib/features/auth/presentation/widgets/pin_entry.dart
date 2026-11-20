import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/numeric_keypad.dart';

/// 6 PIN dots + the PIN keypad. [onChanged] gets the new value (digits only, at most 6).
class PinEntry extends StatelessWidget {
  const PinEntry({super.key, required this.title, this.subtitle, required this.pin, required this.onChanged});

  final String title;
  final String? subtitle;
  final String pin;
  final ValueChanged<String> onChanged;

  void _key(String k) {
    if (k == NumericKeypad.backspace) {
      if (pin.isNotEmpty) onChanged(pin.substring(0, pin.length - 1));
    } else if (pin.length < 6) {
      onChanged(pin + k);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: AppText.s(20, weight: AppText.w700))),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppText.s(14, color: AppColors.muted)),
        ],
        const SizedBox(height: 12),
        Semantics(
          label: 'PIN ${pin.length} / 6',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < pin.length ? AppColors.text : AppColors.transparent,
                      border: Border.all(color: i < pin.length ? AppColors.text : AppColors.subtle, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        NumericKeypad(
          keys: NumericKeypad.pinKeys,
          keyHeight: 56,
          gap: 10,
          radius: 14,
          keyColor: AppColors.fill,
          onKey: _key,
        ),
      ],
    );
  }
}
