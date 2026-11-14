import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';

/// Error (red) or notice (amber) box on the auth screens. Announced to
/// screen readers when it appears.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, this.isError = true});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? AppColors.dangerBg : AppColors.tintAmber,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: AppText.s(13, color: isError ? AppColors.dangerInk : AppColors.textStrong)),
      ),
    );
  }
}
