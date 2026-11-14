import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_switch_tile.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/form_section.dart';
import '../../../../core/utils/qty.dart';

/// Accent square scan button.
class ScanSquare extends StatelessWidget {
  const ScanSquare({super.key, this.size = 48, this.iconSize = 22, required this.label});
  final double size;
  final double iconSize;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary,
        borderRadius: AppRadius.inputR,
        child: InkWell(
          borderRadius: AppRadius.inputR,
          onTap: () {},
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: AppIcon(AppIcons.barcode, size: iconSize, color: AppColors.surface)),
          ),
        ),
      ),
    );
  }
}

// ── expiryBatch ────────────────────────────────────────────────────────────
class ExpiryBatchSection extends StatelessWidget {
  const ExpiryBatchSection({
    super.key,
    required this.batchNo,
    required this.expiry,
    required this.onExpiry,
    required this.warnDays,
    required this.onWarnDays,
    this.batchError,
    this.showBatch = true,
  });

  /// False when editing a saved product: batches are received as stock, not edited here.
  final bool showBatch;

  final TextEditingController batchNo;

  /// Validation message for the batch number (server limits).
  final String? batchError;
  final DateTime? expiry;
  final ValueChanged<DateTime> onExpiry;
  final int warnDays;
  final ValueChanged<int> onWarnDays;

  /// Product without an expiry (soap, diapers…): no expiryAlertDays, no batch needed.
  static const noExpiry = 0;

  static const warnOptions = [
    (30, 'ရက် ၃၀ အလို'),
    (60, 'ရက် ၆၀ အလို'),
    (90, 'ရက် ၉၀ အလို'),
    (noExpiry, 'သက်တမ်း မမှတ်ပါ'),
  ];

  /// Shown under the section (pharmacy decision, item 5).
  static const help =
      "သက်တမ်းမှတ်တဲ့ ပစ္စည်း (ဆေး စသည်) ကို Batch နံပါတ် + သက်တမ်းကုန်ရက်နဲ့ ဖြည့်/ရောင်းပါမယ်။ "
      "သက်တမ်းမရှိတဲ့ ပစ္စည်း (ဆပ်ပြာ၊ ဒိုင်ပါ စသည်) ဆိုရင် 'သက်တမ်း မမှတ်ပါ' ရွေးပါ — Batch မလိုဘဲ ရိုးရိုးပစ္စည်းလို ဖြည့်/ရောင်းပါမယ်။";

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) onExpiry(d);
  }

  @override
  Widget build(BuildContext context) {
    return FormSection(
      title: 'သက်တမ်း နှင့် Batch',
      borderColor: AppColors.pharmacyBorder,
      children: [
        if (showBatch && warnDays != noExpiry)
        TwoCol(
          LabeledField(
            label: 'Batch နံပါတ်',
            small: true,
            error: batchError,
            child: AppInput(key: const ValueKey('batchNo'), controller: batchNo, semanticLabel: 'Batch နံပါတ်'),
          ),
          LabeledField(
            label: 'သက်တမ်းကုန်ရက်',
            small: true,
            child: Semantics(
              button: true,
              label: 'သက်တမ်းကုန်ရက်',
              child: InkWell(
                onTap: () => _pickDate(context),
                borderRadius: AppRadius.inputR,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.inputR,
                    border: Border.all(color: AppColors.inputBorder, width: 1.5),
                  ),
                  child: Text(
                    expiry == null ? '' : DateFormat('yyyy-MM-dd').format(expiry!),
                    style: AppText.s(14),
                  ),
                ),
              ),
            ),
          ),
        ),
        LabeledField(
          label: 'ကုန်ခါနီးရင် သတိပေးမယ်',
          small: true,
          child: AppSelect<int>(
            key: const ValueKey('expiryWarn'),
            label: 'ကုန်ခါနီးရင် သတိပေးမယ်',
            items: warnOptions,
            value: warnDays,
            onChanged: onWarnDays,
          ),
        ),
        if (warnDays != noExpiry)
          Text('Batch တစ်ခုထက်ပိုရင် သက်တမ်းစောတာကို အရင်ရောင်းအောင် ညွှန်ပေးပါမယ် (FEFO)',
              style: AppText.s(12, color: AppColors.muted)),
        Text(help, key: const ValueKey('expiryHelp'), style: AppText.s(12, color: AppColors.muted)),
      ],
    );
  }
}

// ── serialWarranty ─────────────────────────────────────────────────────────
class SerialWarrantySection extends StatefulWidget {
  const SerialWarrantySection({
    super.key,
    required this.serial,
    required this.onSerialChanged,
    required this.imeis,
    required this.onAddImei,
    required this.warrantyMonths,
    required this.onWarrantyChanged,
    this.showSerials = true,
    this.registerCommit,
  });

  /// False when editing a saved product: IMEIs are stock, entered when goods arrive.
  final bool showSerials;

  /// Receives the "add what is typed" callback the form calls on save (BUG-19).
  final ValueSetter<bool Function()>? registerCommit;

  final bool serial;
  final ValueChanged<bool> onSerialChanged;
  final List<String> imeis;

  /// Adds an IMEI; returns an error message (Burmese) to show instead, or null.
  final String? Function(String imei) onAddImei;

  /// 0 = none.
  final int warrantyMonths;
  final ValueChanged<int> onWarrantyChanged;

  /// (months, label) as in the design's select.
  static const warranties = [(0, 'မရှိ'), (3, '၃ လ'), (6, '၆ လ'), (12, '၁ နှစ်')];

  @override
  State<SerialWarrantySection> createState() => _SerialWarrantySectionState();
}

class _SerialWarrantySectionState extends State<SerialWarrantySection> {
  final _imei = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.registerCommit?.call(_commitTyped);
  }

  /// A typed IMEI not yet added: add it now; false (message shown) if refused (BUG-19).
  bool _commitTyped() {
    if (!widget.serial || _imei.text.trim().isEmpty) return true;
    _submit();
    return _error == null;
  }

  @override
  void dispose() {
    _imei.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _imei.text.trim();
    if (v.isEmpty) return;
    final error = widget.onAddImei(v);
    setState(() => _error = error);
    if (error == null) _imei.clear();
  }

  @override
  Widget build(BuildContext context) {
    return FormSection(
      borderColor: AppColors.phoneBorder,
      children: [
        if (widget.showSerials)
        AppSwitchTile(
          title: 'တစ်လုံးချင်း IMEI / Serial မှတ်မယ်',
          description: 'ရောင်းတဲ့အခါ ဘယ်တစ်လုံးလဲ ရွေးရမယ်',
          titleSize: 15,
          padding: EdgeInsets.zero,
          value: widget.serial,
          onChanged: widget.onSerialChanged,
        ),
        if (widget.serial && widget.showSerials)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppInput(
                      key: const ValueKey('imei'),
                      controller: _imei,
                      height: 44,
                      hint: 'IMEI 15 လုံး',
                      keyboardType: TextInputType.number,
                      semanticLabel: 'IMEI ထည့်ရန်',
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'IMEI scan',
                    excludeSemantics: true,
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: AppRadius.inputR,
                      child: InkWell(
                        borderRadius: AppRadius.inputR,
                        onTap: () {},
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: AppIcon(AppIcons.barcode, size: 20, color: AppColors.surface)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Semantics(liveRegion: true, child: Text(_error!, style: AppText.s(12, color: AppColors.danger))),
              ],
              if (widget.imeis.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final i in widget.imeis)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: const BoxDecoration(color: AppColors.serialChipBg, borderRadius: AppRadius.chipR),
                        child: Text(i, style: AppText.s(12, weight: AppText.w600, color: AppColors.serialChipFg)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text('Stock = ထည့်ထားတဲ့ IMEI အရေအတွက် (${widget.imeis.length})',
                  style: AppText.s(12, color: AppColors.muted)),
            ],
          ),
        LabeledField(
          label: 'အာမခံ (ပြေစာပေါ် ပါမယ်)',
          small: true,
          child: AppSelect<int>(
            label: 'အာမခံ',
            items: SerialWarrantySection.warranties,
            value: widget.warrantyMonths,
            onChanged: widget.onWarrantyChanged,
          ),
        ),
      ],
    );
  }
}

// ── variants ───────────────────────────────────────────────────────────────
class VariantsSection extends StatelessWidget {
  const VariantsSection({
    super.key,
    required this.sizes,
    required this.colors,
    required this.onToggleSize,
    required this.onToggleColor,
    required this.stock,
    required this.onStockChanged,
  });

  final Map<String, bool> sizes;
  final Map<String, bool> colors;
  final ValueChanged<String> onToggleSize;
  final ValueChanged<String> onToggleColor;
  /// Variant label -> stock in milli-units.
  final Map<String, int> stock;
  final void Function(String variant, int milli) onStockChanged;

  static const swatches = {
    'အနက်': AppColors.swatchBlack,
    'အဖြူ': AppColors.swatchWhite,
    'အပြာ': AppColors.swatchBlue,
    'အနီ': AppColors.swatchRed,
  };

  static List<String> variantsOf(Map<String, bool> sizes, Map<String, bool> colors) => [
        for (final s in sizes.entries.where((e) => e.value))
          for (final c in colors.entries.where((e) => e.value)) '${s.key} · ${c.key}',
      ];

  @override
  Widget build(BuildContext context) {
    final variants = variantsOf(sizes, colors);
    return FormSection(
      title: 'Size နှင့် အရောင်',
      borderColor: AppColors.fashionBorder,
      children: [
        LabeledField(
          label: 'Size',
          small: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in sizes.entries)
                _chip(
                  selected: e.value,
                  onTap: () => onToggleSize(e.key),
                  bg: e.value ? AppColors.text : AppColors.surface,
                  border: e.value ? AppColors.text : AppColors.inputBorder,
                  minWidth: 48,
                  child: Text(e.key,
                      style: AppText.s(14,
                          weight: AppText.w700, color: e.value ? AppColors.surface : AppColors.textSecondary, height: 1.2)),
                ),
            ],
          ),
        ),
        LabeledField(
          label: 'အရောင်',
          small: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in colors.entries)
                _chip(
                  selected: e.value,
                  onTap: () => onToggleColor(e.key),
                  bg: e.value ? AppColors.fashionSelBg : AppColors.surface,
                  border: e.value ? AppColors.fashionSelBorder : AppColors.inputBorder,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: swatches[e.key],
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.subtle),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(e.key, style: AppText.s(13, weight: AppText.w600, height: 1.2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.inputR,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppColors.fillSoft,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Variant (${variants.length})',
                        style: AppText.s(12, weight: AppText.w700, color: AppColors.textSecondary)),
                    Text('Stock', style: AppText.s(12, weight: AppText.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              for (final v in variants)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.fill))),
                  child: Row(
                    children: [
                      Expanded(child: Text(v, style: AppText.s(14))),
                      SizedBox(
                        width: 64,
                        child: AppInput(
                          key: ValueKey(v),
                          height: 34,
                          radius: 8,
                          fontSize: 14,
                          horizontalPadding: 8,
                          initialValue: stock[v] == null ? null : Qty.format(stock[v]!),
                          hint: '0',
                          keyboardType: TextInputType.number,
                          semanticLabel: '$v stock',
                          onChanged: (s) => onStockChanged(v, Qty.parse(s, decimal: false) ?? 0),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required bool selected,
    required VoidCallback onTap,
    required Color bg,
    required Color border,
    required Widget child,
    double minWidth = 0,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 40,
            constraints: BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
