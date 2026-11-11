import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../../core/widgets/stat_card.dart';
import '../../sales/presentation/sale_ui.dart';
import '../data/report_providers.dart';
import '../domain/report.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportPeriod _period = ReportPeriod.week;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportProvider(_period));
    final s = report.summary;
    final top = MediaQuery.paddingOf(context).top;

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Container(
          color: AppColors.surface,
          padding: EdgeInsets.fromLTRB(20, 20 + top, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('အစီရင်ခံစာ', style: AppText.s(22, weight: AppText.w700)),
                    ),
                  ),
                  SmallOutlineButton(icon: AppIcons.download, label: 'Excel', onPressed: () {}),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedTabs<ReportPeriod>(
                options: [for (final p in ReportPeriod.values) (p, p.label)],
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.cardLg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ရောင်းရငွေ · ${s.range}',
                  style: AppText.s(13, color: AppColors.surface.withValues(alpha: 0.9))),
              const SizedBox(height: 2),
              MoneyText(s.sales, size: 30, color: AppColors.surface, letterSpacing: -0.5, unitSize: 15),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'အမြတ်',
                  value: formatKs(s.profit),
                  valueColor: AppColors.success,
                  valueSize: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(width: AppSpacing.gap),
              Expanded(
                child: StatCard(
                  label: 'အရောင်းအကြိမ်',
                  value: '${s.count} ကြိမ်',
                  valueSize: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.all(16),
          child: _WeekChart(days: report.last7Days),
        ),
        AppCard(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ငွေပေးချေမှု အမျိုးအစား', style: AppText.s(15, weight: AppText.w700)),
              for (final p in report.paymentShares) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(p.method.label, style: AppText.s(13, weight: AppText.w600)),
                    Text('${p.percent}%', style: AppText.s(13, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: AppRadius.chipR,
                  child: Container(
                    height: 8,
                    color: AppColors.fill,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: p.percent / 100,
                      child: Container(
                        decoration: BoxDecoration(color: p.method.color, borderRadius: AppRadius.chipR),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('အရောင်းရဆုံး ပစ္စည်းများ', style: AppText.s(15, weight: AppText.w700)),
              ),
              DividedColumn(dividerOnTop: true, children: [
                for (final (i, t) in report.topProducts.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        InitialAvatar(
                          initial: '${i + 1}',
                          bg: AppColors.fill,
                          fg: AppColors.text,
                          size: 28,
                          fontSize: 13,
                          radius: 8,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: AppText.s(14, weight: AppText.w600)),
                              Text(t.qtyLabel, style: AppText.s(12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        MoneyText(t.amount, size: 14, showUnit: false),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});
  final List<DaySales> days;

  @override
  Widget build(BuildContext context) {
    final max = days.map((d) => d.amount).reduce((a, b) => a > b ? a : b);
    final peak = days.firstWhere((d) => d.amount == max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('နောက်ဆုံး ၇ ရက်', style: AppText.s(15, weight: AppText.w700))),
            Text('ထောင်ကျပ် (K)', style: AppText.s(12, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'နောက်ဆုံး ၇ ရက် နေ့စဉ်ရောင်းရငွေ ဇယား၊ အမြင့်ဆုံးက ${peak.day}နေ့ ${(max / 1000).round()}K',
          excludeSemantics: true,
          child: SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${(days[i].amount / 1000).round()}',
                            style: AppText.s(11, weight: AppText.w600, color: AppColors.textSecondary, height: 1.4)),
                        const SizedBox(height: 4),
                        Container(
                          height: (days[i].amount / max * 120).roundToDouble(),
                          decoration: BoxDecoration(
                            color: i == days.length - 1 ? AppColors.primary : AppColors.chartBar,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6), bottom: Radius.circular(2)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(days[i].day,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: AppText.s(11, color: AppColors.muted, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
