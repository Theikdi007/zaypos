import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/db/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/card_list_tile.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../domain/sync_labels.dart';

/// "စစ်ရန် (n)" (§7): units the server rejected (they block the outbox) and
/// sync issues the owner should look at.
class SyncReviewScreen extends ConsumerWidget {
  const SyncReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejected = ref.watch(rejectedUnitsProvider).value ?? const <OutboxRow>[];
    final issues = ref.watch(openIssuesProvider).value ?? const <SyncIssueRow>[];
    final isOwner = ref.watch(sessionProvider.select((s) => s.isOwner));
    final now = DateTime.now();

    Widget section(String t) => SectionTitle(t,
        size: 13, color: AppColors.textSecondary, margin: const EdgeInsets.fromLTRB(20, 18, 20, 8));

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'စစ်ရန် (${mmDigits(rejected.length + issues.length)})', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (rejected.isEmpty && issues.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('စစ်ရန် မရှိပါ။ အားလုံး sync ဖြစ်နေပါတယ်။',
                        textAlign: TextAlign.center, style: AppText.s(14, color: AppColors.muted)),
                  ),
                if (rejected.isNotEmpty) ...[
                  section('Server က လက်မခံသေးတဲ့ စာရင်း'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('ဒီစာရင်း မပြင်မချင်း နောက်ပိုင်း စာရင်းတွေ server ကို မပို့နိုင်ပါ။',
                        style: AppText.s(12, color: AppColors.dangerInk)),
                  ),
                  AppCard(
                    child: DividedColumn(children: [
                      for (final o in rejected)
                        CardListTile(
                          title: Text(unitSummary(o.kind, SyncStore.rowsOf(o)), style: AppText.s(14, weight: AppText.w600)),
                          subtitle: Text(o.rejectReason ?? '', style: AppText.s(12, color: AppColors.muted)),
                          trailing: const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.subtle),
                          onTap: () => context.push(Routes.rejectedUnit(o.seq)),
                        ),
                    ]),
                  ),
                ],
                if (issues.isNotEmpty) ...[
                  section('စစ်ဆေးရန် ကိစ္စများ'),
                  AppCard(
                    child: DividedColumn(children: [
                      for (final i in issues)
                        CardListTile(
                          title: Text(issueKindLabel(i.kind), style: AppText.s(14, weight: AppText.w600)),
                          subtitle: Text('${i.detail}\n${entryDateLabel(i.createdAt, now)}',
                              style: AppText.s(12, color: AppColors.muted)),
                          isThreeLine: true,
                          trailing: isOwner
                              ? TextButton(
                                  onPressed: () => _resolve(context, ref, i.id),
                                  child: Text('စစ်ပြီးပြီ',
                                      style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
                                )
                              : null,
                        ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncEngineProvider).resolveIssue(id);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
