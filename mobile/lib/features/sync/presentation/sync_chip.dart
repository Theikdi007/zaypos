import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/offline_sync_chip.dart';

/// Dashboard status (§7): online + synced / n waiting / offline / sync problem.
/// A problem opens the "စစ်ရန်" list.
class SyncChip extends ConsumerWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncChipProvider);
    final chip = switch (s.kind) {
      SyncChipKind.hidden => null,
      SyncChipKind.synced => const OfflineSyncChip(label: 'Sync ပြီး', tone: ChipTone.success, icon: AppIcons.check),
      SyncChipKind.waiting => OfflineSyncChip(
          label: s.waiting > 0 ? 'sync ${mmDigits(s.waiting)} ခုစောင့်' : 'sync လုပ်နေသည်',
          icon: AppIcons.send,
        ),
      SyncChipKind.offline =>
        OfflineSyncChip(label: s.waiting > 0 ? 'Offline · sync ${mmDigits(s.waiting)} ခုစောင့်' : 'Offline'),
      SyncChipKind.problem => OfflineSyncChip(
          label: 'Sync ပြဿနာ (${mmDigits(s.problems)})',
          tone: ChipTone.danger,
          icon: AppIcons.shield,
        ),
    };
    if (chip == null) return const SizedBox.shrink();
    return Semantics(
      button: s.kind == SyncChipKind.problem,
      child: GestureDetector(
        onTap: s.kind == SyncChipKind.problem ? () => context.push(Routes.syncReview) : null,
        child: chip,
      ),
    );
  }
}
