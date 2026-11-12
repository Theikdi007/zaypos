import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_icons.dart';

enum ChipTone { warning, danger, success }

/// "Offline · sync ၃ ခုစောင့်" pill (warning), "Sync ပြဿနာ" (danger),
/// "Sync ပြီး" (success).
class OfflineSyncChip extends StatelessWidget {
  const OfflineSyncChip({super.key, required this.label, this.tone = ChipTone.warning, this.icon = AppIcons.wifiOff});

  final String label;
  final ChipTone tone;

  /// SVG path (AppIcons); null = no icon.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.warning => (AppColors.offlineBg, AppColors.debtInk),
      ChipTone.danger => (AppColors.dangerBg, AppColors.dangerInk),
      ChipTone.success => (AppColors.successBg, AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.chipR),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label, style: AppText.s(12, weight: AppText.w600, color: fg, height: 1.6)),
        ],
      ),
    );
  }
}
