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
import '../../../core/widgets/common.dart';
import '../domain/ui_prefs.dart';

class _Module {
  const _Module(this.flag, this.title, this.desc, {this.soon = false});
  final FeatureFlag? flag; // null = not available yet (v2)
  final String title;
  final String desc;
  final bool soon;
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
          '${template.productBadge ?? template.label} ပစ္စည်း ${mmDigits(template.presetCount)} barcode နဲ့'),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
