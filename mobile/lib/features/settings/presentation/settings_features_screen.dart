import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/features/tenant_features.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_switch_tile.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/widgets/card_list_tile.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/ui_prefs.dart';

class _Module {
  const _Module(this.flag, this.title, this.desc, {this.soon = false});
  final FeatureFlag? flag; // null = not available yet (v2)
  final String title;
  final String desc;
  final bool soon;
}

/// Settings → Sync (§7): last sync, waiting units, sync now, "စစ်ရန် (n)".
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(syncEngineProvider);
    final snap = ref.watch(syncSnapshotProvider).value ?? engine.snapshot;
    if (!snap.enabled) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Demo ဆိုင်ကို server နဲ့ sync မလုပ်ပါ။', style: AppText.s(13, color: AppColors.muted)),
        ),
      );
    }
    final counts = ref.watch(outboxCountsProvider).value ?? const OutboxCounts();
    final review = counts.rejected + (ref.watch(openIssuesProvider).value?.length ?? 0);
    final last = snap.lastSyncAt;
    final now = DateTime.now();
    return AppCard(
      child: DividedColumn(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                last == null ? 'နောက်ဆုံး sync: မလုပ်ရသေးပါ' : 'နောက်ဆုံး sync: ${dayLabel(last, now)} ${timeLabel(last)}',
                style: AppText.s(14, weight: AppText.w600),
              ),
              const SizedBox(height: 2),
              Text('ပို့ရန်စောင့်: ${mmDigits(counts.pending)} ခု', style: AppText.s(13, color: AppColors.muted)),
              if (snap.lastError != null) ...[
                const SizedBox(height: 4),
                Text(snap.lastError!, style: AppText.s(12, color: AppColors.dangerInk)),
              ],
              const SizedBox(height: 10),
              PrimaryButton(
                label: snap.running ? 'sync လုပ်နေသည်…' : 'ယခု sync လုပ်မယ်',
                height: 44,
                fontSize: 14,
                onPressed: snap.running ? null : () => engine.syncNow(manual: true),
              ),
            ],
          ),
        ),
        CardListTile(
          title: Text('စစ်ရန် (${mmDigits(review)})',
              style: AppText.s(14, weight: AppText.w600, color: review > 0 ? AppColors.dangerInk : AppColors.text)),
          trailing: const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.subtle),
          onTap: () => context.push(Routes.syncReview),
        ),
      ]),
    );
  }
}

class SettingsFeaturesScreen extends ConsumerWidget {
  const SettingsFeaturesScreen({super.key});

  static const _core = ['ရောင်းခြင်း (POS)', 'အကြွေးစာအုပ်', 'ငွေသား / KBZPay / WavePay', 'နေ့စဉ် Report', 'Offline + Sync'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(shopTemplateProvider);
    final features = ref.watch(tenantFeaturesProvider);
    final simple = ref.watch(simpleModeProvider);
    final modules = [
      const _Module(FeatureFlag.quickSale, 'Quick Sale', 'ပစ္စည်းမထည့်ဘဲ ဈေးနှုန်းရိုက်ပြီး ရောင်း'),
      const _Module(FeatureFlag.stock, 'Stock မှတ်ခြင်း', 'ရောင်းတိုင်း နုတ် · နည်းရင် သတိပေး'),
      _Module(FeatureFlag.presetCatalog, 'ကြိုတင်ပစ္စည်းစာရင်း',
          template.presetCount > 0
              ? '${template.productBadge ?? template.label} ပစ္စည်း ${mmDigits(template.presetCount)} မျိုး'
              : 'ဒီဆိုင်အမျိုးအစားအတွက် မရှိသေးပါ'),
      const _Module(FeatureFlag.expiryBatch, 'သက်တမ်းကုန်ရက် / Batch', 'ဆေးဆိုင်၊ အစားအသောက်'),
      const _Module(FeatureFlag.serialWarranty, 'IMEI / Serial + အာမခံ', 'ဖုန်း၊ Electronics'),
      const _Module(FeatureFlag.variants, 'Size / အရောင်', 'အဝတ်အထည်၊ ဖိနပ်၊ အလှကုန်'),
      const _Module(FeatureFlag.decimalQty, 'ဒသမ အရေအတွက်', '2.5 ပေ · 0.75 ကီလို'),
      const _Module(FeatureFlag.quotation, 'ဈေးနှုန်းတင်ပြချက် (Quotation)', 'ကန်ထရိုက်တာ / လက်ကား'),
      const _Module(FeatureFlag.serviceItems, 'ဝန်ဆောင်မှု item', 'Stock မလို · ဆံပင်ညှပ်၊ ပြင်ဆင်ခ'),
      const _Module(null, 'စားပွဲ / Order mode', 'စားသောက်ဆိုင်၊ ကော်ဖီဆိုင်', soon: true),
    ];

    Widget section(String t) => SectionTitle(t,
        size: 13, color: AppColors.textSecondary, margin: const EdgeInsets.fromLTRB(20, 18, 20, 8));

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'ဆိုင် Features', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.cardR),
                  child: Row(
                    children: [
                      InitialAvatar(
                        initial: template.initial,
                        bg: AppColors.onPrimaryOverlay,
                        fg: AppColors.surface,
                        size: 44,
                        fontSize: 18,
                        radius: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('လက်ရှိ template',
                                style: AppText.s(12, color: AppColors.surface.withValues(alpha: 0.9))),
                            Text(template.label,
                                style: AppText.s(16, weight: AppText.w700, color: AppColors.surface)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Material(
                        color: AppColors.surface,
                        borderRadius: AppRadius.inputR,
                        child: InkWell(
                          borderRadius: AppRadius.inputR,
                          onTap: () => context.push('${Routes.register}?step=2'),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            child: Text('ပြောင်းမယ်',
                                style: AppText.s(13, weight: AppText.w700, color: AppColors.success)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                section('အခြေခံ (ဆိုင်တိုင်း ပါပြီးသား)'),
                AppCard(
                  child: DividedColumn(children: [
                    for (final c in _core)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(child: Text(c, style: AppText.s(14, weight: AppText.w600))),
                            const SizedBox(width: 12),
                            const AppIcon(AppIcons.check,
                                size: 18, strokeWidth: 2.4, color: AppColors.success, semanticLabel: 'ဖွင့်ထားသည်'),
                          ],
                        ),
                      ),
                  ]),
                ),
                section('ထပ်ဖွင့်လို့ရတဲ့ Features'),
                AppCard(
                  child: DividedColumn(children: [
                    for (final m in modules)
                      AppSwitchTile(
                        title: m.title,
                        description: m.desc,
                        enabled: !m.soon,
                        value: m.flag?.read(features) ?? false,
                        onChanged: m.flag == null
                            ? null
                            : (v) => ref.read(tenantFeaturesProvider.notifier).set(m.flag!, v),
                        badges: [
                          if (m.flag != null && m.flag!.read(template.features))
                            const TinyBadge('template', bg: AppColors.successBg, fg: AppColors.success),
                          if (m.soon) const TinyBadge('v2', bg: AppColors.fill, fg: AppColors.textSecondary),
                        ],
                      ),
                  ]),
                ),
                section('အသုံးပြုပုံ'),
                AppCard(
                  child: AppSwitchTile(
                    title: 'ရိုးရှင်း mode',
                    description: 'စာလုံးကြီး၊ ခလုတ်ကြီး၊ menu နည်းနည်း',
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    value: simple,
                    onChanged: (v) => ref.read(simpleModeProvider.notifier).set(v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'Feature ပိတ်လိုက်ရင်လည်း မှတ်ထားပြီးသား data တွေ မပျက်ပါ။ ပြန်ဖွင့်ရင် ပြန်ပေါ်ပါမယ်။',
                    style: AppText.s(12, color: AppColors.muted),
                  ),
                ),
                section('Sync'),
                const _SyncSection(),
                section('အကောင့်'),
                AppCard(
                  child: DividedColumn(children: [
                    CardListTile(
                      title: Text('ဖုန်းများ', style: AppText.s(14, weight: AppText.w600)),
                      subtitle: Text('ဒီဆိုင်က ဖုန်းတွေ · ပျောက်သွားတဲ့ဖုန်း ဖယ်ရန်', style: AppText.s(12, color: AppColors.muted)),
                      trailing: const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.subtle),
                      onTap: () => context.push(Routes.devices),
                    ),
                    CardListTile(
                      title: Text('ထွက်မယ်', style: AppText.s(14, weight: AppText.w600, color: AppColors.danger)),
                      subtitle: Text('ဒီဖုန်းထဲက စာရင်းတွေ မပျက်ပါ။ ပြန်ဝင်ရင် ဆက်သုံးလို့ရပါတယ်။',
                          style: AppText.s(12, color: AppColors.muted)),
                      onTap: () => ref.read(authControllerProvider.notifier).signOut(),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
