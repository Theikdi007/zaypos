import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_icons.dart';

/// "Offline · sync ၃ ခုစောင့်" pill.
class OfflineSyncChip extends StatelessWidget {
  const OfflineSyncChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(color: AppColors.offlineBg, borderRadius: AppRadius.chipR),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(AppIcons.wifiOff, size: 14, color: AppColors.debtInk),
          const SizedBox(width: 6),
          Text(label,
              style: AppText.s(12, weight: AppText.w600, color: AppColors.debtInk, height: 1.6)),
        ],
      ),
    );
  }
}
