import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_bottom_nav.dart';
import 'routes.dart';

/// Shell for the tabs that show the bottom nav. Nav index 1 (ရောင်းမယ်)
/// opens the full-screen POS instead of a tab, as in the design.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // nav index -> branch index (POS has no branch)
  static const _branchForNav = {0: 0, 2: 1, 3: 2, 4: 3};
  static const _navForBranch = {0: 0, 1: 2, 2: 3, 3: 4};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: AppBottomNav(
        currentIndex: _navForBranch[shell.currentIndex]!,
        onTap: (i) {
          if (i == 1) {
            context.push(Routes.pos);
            return;
          }
          final b = _branchForNav[i]!;
          shell.goBranch(b, initialLocation: b == shell.currentIndex);
        },
      ),
    );
  }
}
