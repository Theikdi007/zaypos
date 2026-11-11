import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_icons.dart';

class AppNavItem {
  const AppNavItem(this.icon, this.label);
  final String icon;
  final String label;
}

/// Five-item bottom navigation: ပင်မ / ရောင်းမယ် / ပစ္စည်း / အကြွေး / Report.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const items = [
    AppNavItem(AppIcons.home, 'ပင်မ'),
    AppNavItem(AppIcons.cart, 'ရောင်းမယ်'),
    AppNavItem(AppIcons.box, 'ပစ္စည်း'),
    AppNavItem(AppIcons.ledger, 'အကြွေး'),
    AppNavItem(AppIcons.chart, 'Report'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: AppSizes.bottomNav + bottomInset,
      padding: EdgeInsets.only(bottom: 10 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(child: _NavButton(item: items[i], active: i == currentIndex, onTap: () => onTap(i))),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.muted;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(item.icon, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: AppText.s(11, weight: active ? AppText.w700 : AppText.w400, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
