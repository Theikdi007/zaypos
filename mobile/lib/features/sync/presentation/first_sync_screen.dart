import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/session.dart';
import '../../auth/presentation/widgets/auth_message.dart';

/// First sign-in on a phone (§5.4): the whole shop is downloaded before the
/// app opens, so an empty phone never pushes on top of a shop it hasn't seen.
/// The router leaves this screen when the download completes.
class FirstSyncScreen extends ConsumerStatefulWidget {
  const FirstSyncScreen({super.key});

  @override
  ConsumerState<FirstSyncScreen> createState() => _FirstSyncScreenState();
}

class _FirstSyncScreenState extends ConsumerState<FirstSyncScreen> {
  void _retry() => unawaited(ref.read(syncEngineProvider).syncNow(manual: true));

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(syncSnapshotProvider).value ?? ref.watch(syncEngineProvider).snapshot;
    final shop = ref.watch(sessionProvider.select((s) => s.shopName));
    final rows = snap.downloadedRows;
    final failed = !snap.running && snap.lastError != null;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppIcon(AppIcons.download, size: 40, color: AppColors.primary)),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(shop, textAlign: TextAlign.center, style: AppText.s(20, weight: AppText.w700)),
              ),
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  'ဆိုင်ဒေတာ ဒေါင်းနေသည်… ${formatMoney(rows ?? 0)} / ?',
                  textAlign: TextAlign.center,
                  style: AppText.s(15, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 20),
              if (!failed) const LinearProgressIndicator(minHeight: 6, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                'ပထမဆုံးအကြိမ် ဆိုင်ရဲ့ ပစ္စည်း၊ ဖောက်သည်၊ အရောင်း စာရင်းတွေကို ဒီဖုန်းထဲ ကူးနေပါတယ်။ ပြီးရင် အင်တာနက်မရှိလည်း သုံးလို့ရပါပြီ။',
                textAlign: TextAlign.center,
                style: AppText.s(13, color: AppColors.muted),
              ),
              if (failed) ...[
                const SizedBox(height: 20),
                AuthMessage(snap.lastError!),
                const SizedBox(height: 12),
                PrimaryButton(label: 'ပြန်ကြိုးစားမယ်', onPressed: _retry),
              ],
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                  child: Text('ထွက်မယ်', style: AppText.s(13, weight: AppText.w600, color: AppColors.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
