import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_switch_tile.dart' show TinyBadge;
import '../../../core/widgets/card_list_tile.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/session.dart';
import '../../auth/presentation/widgets/auth_message.dart';
import '../data/devices_api.dart';

/// Settings → ဖုန်းများ (§7): the shop's phones from `GET /devices`. The owner
/// can remove a lost phone; it then can't sync or sign in again, and its
/// receipt prefix is never reused.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  static String title(RemoteDevice d) => [
        'ဖုန်း ${d.code}',
        if (d.name != null && d.name!.isNotEmpty) d.name!,
      ].join(' · ');

  Future<void> _remove(BuildContext context, WidgetRef ref, RemoteDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${title(d)} ကို ဖယ်မလား?'),
        content: const Text(
          'ဒီဖုန်း ပျောက်သွားရင် (သို့) မသုံးတော့ရင် ဖယ်ပါ။ ဖယ်ပြီးရင် ဒီဆိုင်နဲ့ sync လုပ်လို့ မရတော့ပါ။ '
          'အဲဒီဖုန်းထဲမှာ မပို့ရသေးတဲ့ စာရင်းတွေ ရှိရင် ပျောက်သွားနိုင်ပါတယ်။',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မဖယ်တော့ပါ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ဖယ်မယ်', style: AppText.s(14, weight: AppText.w700, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(devicesApiProvider).remove(d.id);
      ref.invalidate(remoteDevicesProvider);
      // Other screens see the device go on the next pull.
      unawaited(ref.read(syncEngineProvider).syncNow(manual: true));
      messenger.showSnackBar(SnackBar(content: Text('${title(d)} ကို ဖယ်ပြီးပါပြီ။')));
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(remoteDevicesProvider);
    final session = ref.watch(sessionProvider);
    final now = DateTime.now();
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'ဖုန်းများ', onBack: () => context.pop()),
          Expanded(
            child: session.isDemo
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Demo ဆိုင်မှာ ဖုန်းစာရင်း မရှိပါ။', style: AppText.s(14, color: AppColors.muted)),
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(remoteDevicesProvider.future),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 12, bottom: 24),
                      children: switch (devices) {
                        AsyncData(:final value) => [
                            AppCard(
                              child: DividedColumn(children: [
                                for (final d in value)
                                  CardListTile(
                                    title: Row(
                                      children: [
                                        Flexible(child: Text(title(d), style: AppText.s(14, weight: AppText.w600))),
                                        if (d.isCurrent) ...[
                                          const SizedBox(width: 8),
                                          const TinyBadge('ဒီဖုန်း', bg: AppColors.successBg, fg: AppColors.success),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      [
                                        'ပြေစာ ${d.code}-${d.lastSeq.toString().padLeft(4, '0')} အထိ',
                                        d.lastSyncAt == null
                                            ? 'sync မလုပ်ရသေး'
                                            : 'sync: ${dayLabel(d.lastSyncAt!, now)} ${timeLabel(d.lastSyncAt!)}',
                                      ].join(' · '),
                                      style: AppText.s(12, color: AppColors.muted),
                                    ),
                                    trailing: session.isOwner && !d.isCurrent
                                        ? TextButton(
                                            onPressed: () => _remove(context, ref, d),
                                            child: Text('ဖယ်မယ်',
                                                style: AppText.s(13, weight: AppText.w600, color: AppColors.danger)),
                                          )
                                        : null,
                                  ),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Text(
                                'ဖုန်း ${mmDigits(value.length)} လုံး · ဖုန်းတစ်လုံးချင်း ကိုယ်ပိုင် ပြေစာနံပါတ် (A-, B-, …) ရှိပါတယ်။',
                                style: AppText.s(12, color: AppColors.muted),
                              ),
                            ),
                          ],
                        AsyncError(:final error) => [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AuthMessage(error is ApiError ? error.message : '$error'),
                                  const SizedBox(height: 12),
                                  PrimaryButton(
                                    label: 'ပြန်ကြိုးစားမယ်',
                                    onPressed: () => ref.invalidate(remoteDevicesProvider),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        _ => const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
