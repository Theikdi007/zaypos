import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/features/tenant_features.dart';
import '../../../../core/sync/sync_limits.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/utils/qty.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/form_section.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../inventory/presentation/restock_sheet.dart' show ExpiredBadge;
import '../../data/product_providers.dart';
import '../../domain/product.dart' show ProductVariant;
import '../../domain/product_modules.dart';

/// New rows typed in the edit form, saved with the product (one unit).
class PendingModules {
  final imeis = <String>[];
  final batches = <({String batchNo, DateTime? expiry})>[];
  final variants = <({String size, String color})>[];

  bool get isEmpty => imeis.isEmpty && batches.isEmpty && variants.isEmpty;
}

/// Edit form (BUG-12): lists the product's existing IMEIs / batches /
/// sizes-colours and lets the owner add new ones. Nothing is deleted here —
/// sold IMEIs and used batches stay as they are.
class EditModuleSections extends ConsumerStatefulWidget {
  const EditModuleSections({
    super.key,
    required this.productId,
    required this.features,
    required this.pending,
    required this.onChanged,
  });

  final String productId;
  final TenantFeatures features;
  final PendingModules pending;
  final VoidCallback onChanged;

  @override
  ConsumerState<EditModuleSections> createState() => _EditModuleSectionsState();
}

class _EditModuleSectionsState extends ConsumerState<EditModuleSections> {
  final _imei = TextEditingController();
  final _batchNo = TextEditingController();
  final _size = TextEditingController();
  final _color = TextEditingController();
  DateTime? _expiry;
  String? _imeiError;
  String? _batchError;
  String? _variantError;
  final _dates = DateFormat('yyyy-MM-dd');

  PendingModules get _p => widget.pending;

  @override
  void dispose() {
    for (final c in [_imei, _batchNo, _size, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addImei() {
    final limits = ref.read(syncLimitsProvider);
    final v = limits.normalize('productSerials.serial', _imei.text);
    if (v.isEmpty) return;
    final existing = ref.read(productSerialsProvider(widget.productId)).value ?? const [];
    final error = limits.checkText('productSerials.serial', v, label: 'IMEI / Serial') ??
        (_p.imeis.contains(v) || existing.any((s) => s.serial == v) ? 'ဒီ IMEI ရှိပြီးသားပါ။' : null);
    setState(() => _imeiError = error);
    if (error != null) return;
    _p.imeis.add(v);
    _imei.clear();
    widget.onChanged();
  }

  void _addBatch() {
    final limits = ref.read(syncLimitsProvider);
    final no = _batchNo.text.trim();
    final existing = ref.read(productBatchesProvider(widget.productId)).value ?? const [];
    final error = limits.checkText('productBatches.batchNo', no, label: 'Batch နံပါတ်') ??
        (existing.any((b) => b.batchNo == no) || _p.batches.any((b) => b.batchNo == no)
            ? 'ဒီ Batch ရှိပြီးသားပါ။'
            : null);
    setState(() => _batchError = error);
    if (error != null) return;
    _p.batches.add((batchNo: no, expiry: _expiry == null ? null : DateTime.utc(_expiry!.year, _expiry!.month, _expiry!.day)));
    _batchNo.clear();
    setState(() => _expiry = null);
    widget.onChanged();
  }

  void _addVariant() {
    final size = _size.text.trim(), color = _color.text.trim();
    final existing = ref.read(productVariantsProvider(widget.productId)).value ?? const [];
    final error = size.isEmpty || color.isEmpty
        ? 'Size နဲ့ အရောင် ထည့်ပါ။'
        : existing.any((v) => v.size == size && v.color == color) ||
                _p.variants.any((v) => v.size == size && v.color == color)
            ? 'ဒီ Size / အရောင် ရှိပြီးသားပါ။'
            : null;
    setState(() => _variantError = error);
    if (error != null) return;
    _p.variants.add((size: size, color: color));
    _size.clear();
    _color.clear();
    widget.onChanged();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => _expiry = d);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.features;
    final now = DateTime.now();
    final List<ProductSerial> serials =
        f.serialWarranty ? ref.watch(productSerialsProvider(widget.productId)).value ?? const [] : const [];
    final List<ProductBatch> batches =
        f.expiryBatch ? ref.watch(productBatchesProvider(widget.productId)).value ?? const [] : const [];
    final List<ProductVariant> variants =
        f.variants ? ref.watch(productVariantsProvider(widget.productId)).value ?? const [] : const [];
    final variantStock = f.variants ? ref.watch(variantStockProvider).value ?? const {} : const <String, int>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.serialWarranty)
          FormSection(
            title: 'IMEI / Serial',
            borderColor: AppColors.phoneBorder,
            children: [
              if (serials.isEmpty && _p.imeis.isEmpty)
                Text('IMEI မမှတ်ရသေးပါ', style: AppText.s(13, color: AppColors.muted))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in serials)
                      _chip(s.serial, sold: s.status == SerialStatus.sold, key: ValueKey('serial-${s.id}')),
                    for (final i in _p.imeis) _chip(i, isNew: true),
                  ],
                ),
              _addRow(
                AppInput(
                  key: const ValueKey('newImei'),
                  controller: _imei,
                  height: 44,
                  hint: 'IMEI အသစ်',
                  keyboardType: TextInputType.number,
                  semanticLabel: 'IMEI အသစ် ထည့်ရန်',
                  onSubmitted: (_) => _addImei(),
                ),
                _addImei,
                key: const ValueKey('addImei'),
              ),
              if (_imeiError != null) _errorText(_imeiError!),
              Text('IMEI အသစ်တစ်ခု = ဖုန်းတစ်လုံး ဝင်လာ (Stock +1)', style: AppText.s(12, color: AppColors.muted)),
            ],
          ),
        if (f.expiryBatch) ...[
          if (f.serialWarranty) const SizedBox(height: 14),
          FormSection(
            title: 'Batch များ',
            borderColor: AppColors.pharmacyBorder,
            children: [
              if (batches.isEmpty && _p.batches.isEmpty)
                Text('Batch မရှိသေးပါ', style: AppText.s(13, color: AppColors.muted)),
              for (final b in batches)
                Row(
                  key: ValueKey('batch-${b.id}'),
                  children: [
                    Expanded(
                      child: Text(
                        [b.batchNo, if (b.expiryDate != null) _dates.format(b.expiryDate!)].join(' · '),
                        style: AppText.s(14, weight: AppText.w600),
                      ),
                    ),
                    if (b.isExpired(now)) ...[const ExpiredBadge(), const SizedBox(width: 8)],
                    Text('ကျန် ${Qty.format(b.qtyMilli)}', style: AppText.s(13, color: AppColors.muted)),
                  ],
                ),
              for (final b in _p.batches)
                Text('${[b.batchNo, if (b.expiry != null) _dates.format(b.expiry!)].join(' · ')} · အသစ်',
                    style: AppText.s(14, weight: AppText.w600, color: AppColors.primary)),
              TwoCol(
                LabeledField(
                  label: 'Batch အသစ်',
                  small: true,
                  child: AppInput(key: const ValueKey('newBatchNo'), controller: _batchNo, semanticLabel: 'Batch အသစ် နံပါတ်'),
                ),
                LabeledField(
                  label: 'သက်တမ်းကုန်ရက်',
                  small: true,
                  child: Semantics(
                    button: true,
                    label: 'Batch အသစ် သက်တမ်းကုန်ရက်',
                    child: InkWell(
                      key: const ValueKey('newBatchExpiry'),
                      onTap: _pickExpiry,
                      borderRadius: AppRadius.inputR,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.inputR,
                          border: Border.all(color: AppColors.inputBorder, width: 1.5),
                        ),
                        child: Text(_expiry == null ? '' : _dates.format(_expiry!), style: AppText.s(14)),
                      ),
                    ),
                  ),
                ),
              ),
              PrimaryButton(
                key: const ValueKey('addBatch'),
                label: '+ Batch ထည့်မယ်',
                variant: ButtonVariant.soft,
                height: 44,
                radius: 12,
                fontSize: 14,
                onPressed: _addBatch,
              ),
              if (_batchError != null) _errorText(_batchError!),
              Text("Batch အသစ်ထဲ ပစ္စည်းကို 'Stock ဖြည့်မယ်' နဲ့ ထည့်ပါ", style: AppText.s(12, color: AppColors.muted)),
            ],
          ),
        ],
        if (f.variants) ...[
          if (f.serialWarranty || f.expiryBatch) const SizedBox(height: 14),
          FormSection(
            title: 'Size / အရောင်',
            children: [
              for (final v in variants)
                Row(
                  key: ValueKey('variant-${v.id}'),
                  children: [
                    Expanded(child: Text(v.label, style: AppText.s(14, weight: AppText.w600))),
                    Text('ကျန် ${Qty.format(variantStock[v.id] ?? 0)}', style: AppText.s(13, color: AppColors.muted)),
                  ],
                ),
              for (final v in _p.variants)
                Text('${v.size} · ${v.color} · အသစ်', style: AppText.s(14, weight: AppText.w600, color: AppColors.primary)),
              TwoCol(
                LabeledField(
                  label: 'Size',
                  small: true,
                  child: AppInput(key: const ValueKey('newVariantSize'), controller: _size, semanticLabel: 'Size အသစ်'),
                ),
                LabeledField(
                  label: 'အရောင်',
                  small: true,
                  child: AppInput(key: const ValueKey('newVariantColor'), controller: _color, semanticLabel: 'အရောင် အသစ်'),
                ),
              ),
              PrimaryButton(
                key: const ValueKey('addVariant'),
                label: '+ Size / အရောင် ထည့်မယ်',
                variant: ButtonVariant.soft,
                height: 44,
                radius: 12,
                fontSize: 14,
                onPressed: _addVariant,
              ),
              if (_variantError != null) _errorText(_variantError!),
              Text("အသစ်ထဲ ပစ္စည်းကို 'Stock ဖြည့်မယ်' နဲ့ ထည့်ပါ", style: AppText.s(12, color: AppColors.muted)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _addRow(Widget input, VoidCallback onAdd, {Key? key}) => Row(
        children: [
          Expanded(child: input),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: PrimaryButton(
              key: key,
              label: '+ ထည့်',
              variant: ButtonVariant.soft,
              height: 44,
              radius: 12,
              fontSize: 14,
              onPressed: onAdd,
            ),
          ),
        ],
      );

  Widget _chip(String text, {bool sold = false, bool isNew = false, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sold ? AppColors.fill : AppColors.serialChipBg,
          borderRadius: AppRadius.chipR,
        ),
        child: Text(
          sold ? '$text · ရောင်းပြီး' : isNew ? '$text · အသစ်' : text,
          style: AppText.s(12, weight: AppText.w600, color: sold ? AppColors.muted : AppColors.serialChipFg),
        ),
      );

  Widget _errorText(String s) =>
      Semantics(liveRegion: true, child: Text(s, style: AppText.s(12, color: AppColors.danger)));
}
