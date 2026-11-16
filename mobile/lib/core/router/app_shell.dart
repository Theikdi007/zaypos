import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_bottom_nav.dart';
import 'routes.dart';

/// Shell for the tabs that show the bottom nav. Nav index 1 (ရောင်းမယ်)
/// opens the full-screen POS instead of a tab, as in the design.
///
/// System back (BUG-56): on ပစ္စည်း / အကြွေး / အစီရင်ခံစာ it goes to ပင်မ; on
/// ပင်မ it asks before leaving the app (leaving costs a PIN entry on return).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, this.exitApp = _systemExit});

  final StatefulNavigationShell shell;

  /// Leaves the app (a parameter so tests can see it was called).
  final Future<void> Function() exitApp;

  static Future<void> _systemExit() => SystemNavigator.pop();

  // nav index -> branch index (POS has no branch)
  static const _branchForNav = {0: 0, 2: 1, 3: 2, 4: 3};
  static const _navForBranch = {0: 0, 1: 2, 2: 3, 3: 4};

  Future<void> _onBack(BuildContext context) async {
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    if (await confirmExit(context)) await exitApp();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(context);
      },
      child: Scaffold(
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
      ),
    );
  }
}

/// "ZayPOS က ထွက်မလား" — true if the owner chose to leave.
Future<bool> confirmExit(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ZayPOS က ထွက်မလား'),
        content: const Text('ပြန်ဖွင့်ရင် PIN ထည့်ရပါမယ်။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မထွက်ပါ')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('ထွက်မယ်')),
        ],
      ),
    ) ??
    false;
