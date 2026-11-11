import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/common.dart';

/// "+95 | 9 xxx xxx xxx" field (height 52, radius 14).
class PhoneField extends StatelessWidget {
  const PhoneField({super.key, this.controller, this.semanticLabel = 'ဖုန်းနံပါတ်'});

  final TextEditingController? controller;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: controller,
      height: 52,
      radius: 14,
      fontSize: 16,
      horizontalPadding: 14,
      hint: '9 xxx xxx xxx',
      keyboardType: TextInputType.phone,
      semanticLabel: semanticLabel,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
      prefix: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+95', style: AppText.s(15, weight: AppText.w600, color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: AppColors.inputBorder),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
