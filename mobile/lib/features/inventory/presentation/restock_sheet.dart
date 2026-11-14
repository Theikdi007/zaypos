import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/sync/sync_limits.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/qty_sheet.dart';
import '../../products/domain/product.dart' show ProductVariant;
import '../../products/domain/product_modules.dart';

/// "Stock ဖြည့်မယ်": goods received for one product. Whole units, or decimals
/// when [decimal] (TenantFeatures.decimalQty: 2.5 ပေ, 0.75 ကီလို).
/// Returns the quantity (milli-units), or null if dismissed. For an
/// [untracked] product this is its first count, which starts tracking it.
Future<int?> showRestockSheet(
  BuildContext context, {
  required String productName,
  required bool untracked,
  bool decimal = false,
  String unit = 'ခု',
}) =>
    showQtySheet(
      context,
      title: 'Stock ဖြည့်မယ်',
      subtitle: untracked
          ? '$productName · Stock မမှတ်ရသေးပါ။ လက်ရှိ ရှိနေတဲ့ အရေအတွက် ထည့်လိုက်ရင် စမှတ်ပါမယ်။'
          : '$productName · ဝင်လာတဲ့ အရေအတွက် ထည့်ပါ။',
      decimal: decimal,
      unit: unit,
    );

/// What arrived for a module product (BUG-12).
class ModuleRestock {
  const ModuleRestock({
    required this.qtyMilli,
    this.variantId,
    this.batchId,
    this.newBatchNo,
    this.newBatchExpiry,
    this.imeis = const [],
  });

  final int qtyMilli;
  final String? variantId;

  /// An existing batch, or null with [newBatchNo] set for a new one.
  final String? batchId;
  final String? newBatchNo;

  /// Calendar date (UTC midnight) of the new batch.
  final DateTime? newBatchExpiry;

  /// New IMEIs (normalized); qtyMilli = their count.
  final List<String> imeis;
}

/// How goods arrive for a product.
enum RestockMode {
  /// Each phone has its own IMEI: enter / scan the list, count = list size.
  imei,

  /// Into a batch (existing, or a new one with batch no. + expiry) + quantity.
  batch,

  /// Into one size · colour + quantity.
  variant,
}

/// "Stock ဖြည့်မယ်" for an IMEI / batch / size-colour product (BUG-12).
Future<ModuleRestock?> showModuleRestockSheet(
  BuildContext context, {
  required RestockMode mode,
  required String productName,
  bool decimal = false,
  String unit = 'ခု',
  List<ProductSerial> serials = const [],
  List<ProductBatch> batches = const [],
  List<ProductVariant> variants = const [],
  Map<String, int> variantStock = const {},
}) =>
    showModalBottomSheet<ModuleRestock>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ModuleRestockSheet(
        mode: mode,
        productName: productName,
        decimal: decimal,
        unit: unit,
        serials: serials,
        batches: batches,
        variants: variants,
        variantStock: variantStock,
      ),
    );

class ModuleRestockSheet extends ConsumerStatefulWidget {
  const ModuleRestockSheet({
    super.key,
    required this.mode,
    required this.productName,
    this.decimal = false,
    this.unit = 'ခု',
    this.serials = const [],
    this.batches = const [],
    this.variants = const [],
    this.variantStock = const {},
  });

  final RestockMode mode;
  final String productName;
  final bool decimal;
  final String unit;
  final List<ProductSerial> serials;
  final List<ProductBatch> batches;
  final List<ProductVariant> variants;
  final Map<String, int> variantStock;

  /// Batch choice meaning "a new batch".
  static const newBatch = '__new__';

  @override
  ConsumerState<ModuleRestockSheet> createState() => _ModuleRestockSheetState();
}

class _ModuleRestockSheetState extends ConsumerState<ModuleRestockSheet> {
  int _milli = 0;
  final _now = DateTime.now();
  final _dates = DateFormat('yyyy-MM-dd');

  // imei
  final _imei = TextEditingController();
  final _imeis = <String>[];
  String? _error;

  // batch
  late final List<ProductBatch> _batches = [...widget.batches]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  late String _batch = _batches.where((b) => !b.isExpired(_now)).firstOrNull?.id ?? ModuleRestockSheet.newBatch;
  final _batchNo = TextEditingController();
  DateTime? _expiry;

  // variant
  late String? _variant = widget.variants.firstOrNull?.id;

  @override
  void initState() {
    super.initState();
    _imei.addListener(() => setState(() {}));
    _batchNo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _imei.dispose();
    _batchNo.dispose();
    super.dispose();
  }

  /// Adds the typed IMEI to the list; returns false (and shows why) if invalid.
  bool _addImei() {
    final limits = ref.read(syncLimitsProvider);
    final v = limits.normalize('productSerials.serial', _imei.text);
    if (v.isEmpty) return true;
    final error = limits.checkText('productSerials.serial', v, label: 'IMEI / Serial') ??
        (_imeis.contains(v) || widget.serials.any((s) => s.serial == v) ? 'ဒီ IMEI ရှိပြီးသားပါ။' : null);
    setState(() {
      _error = error;
      if (error == null) {
        _imeis.add(v);
        _imei.clear();
      }
    });
    return error == null;
  }

  void _imeiKey(String k) {
    if (k == NumericKeypad.backspace) {
      if (_imei.text.isNotEmpty) _imei.text = _imei.text.substring(0, _imei.text.length - 1);
    } else {
      _imei.text += k;
    }
    _imei.selection = TextSelection.collapsed(offset: _imei.text.length);
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? _now,
      firstDate: DateTime(_now.year - 1),
      lastDate: DateTime(_now.year + 10),
    );
    if (d != null) setState(() => _expiry = d);
  }

  bool get _canSave => switch (widget.mode) {
        RestockMode.imei => _imeis.isNotEmpty || _imei.text.trim().isNotEmpty,
        RestockMode.batch => _milli > 0 && (_batch != ModuleRestockSheet.newBatch || _batchNo.text.trim().isNotEmpty),
        RestockMode.variant => _milli > 0 && _variant != null,
      };

  void _save() {
    switch (widget.mode) {
      case RestockMode.imei:
        if (!_addImei() || _imeis.isEmpty) return;
        Navigator.pop(context, ModuleRestock(qtyMilli: Qty.units(_imeis.length), imeis: List.unmodifiable(_imeis)));
      case RestockMode.batch:
        final isNew = _batch == ModuleRestockSheet.newBatch;
        if (isNew) {
          final limits = ref.read(syncLimitsProvider);
          final error = limits.checkText('productBatches.batchNo', _batchNo.text.trim(), label: 'Batch နံပါတ်');
          if (error != null) {
            setState(() => _error = error);
            return;
          }
        }
        Navigator.pop(
          context,
          ModuleRestock(
            qtyMilli: _milli,
            batchId: isNew ? null : _batch,
            newBatchNo: isNew ? _batchNo.text.trim() : null,
            newBatchExpiry: isNew && _expiry != null ? DateTime.utc(_expiry!.year, _expiry!.month, _expiry!.day) : null,
          ),
        );
      case RestockMode.variant:
        Navigator.pop(context, ModuleRestock(qtyMilli: _milli, variantId: _variant));
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + insets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Stock ဖြည့်မယ်', style: AppText.s(18, weight: AppText.w700))),
            const SizedBox(height: 2),
            Text(
              switch (widget.mode) {
                RestockMode.imei => '${widget.productName} · ဝင်လာတဲ့ ဖုန်းတစ်လုံးချင်း IMEI ထည့်ပါ',
                RestockMode.batch => '${widget.productName} · ဘယ် Batch ထဲ ဝင်လာလဲ',
                RestockMode.variant => '${widget.productName} · ဘယ် Size / အရောင် ဝင်လာလဲ',
              },
              style: AppText.s(13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            ...switch (widget.mode) {
              RestockMode.imei => _imeiBody(),
              RestockMode.batch => _batchBody(),
              RestockMode.variant => _variantBody(),
            },
            if (_error != null) ...[
              const SizedBox(height: 6),
              Semantics(liveRegion: true, child: Text(_error!, style: AppText.s(12, color: AppColors.danger))),
            ],
            const SizedBox(height: 12),
            PrimaryButton(label: 'သိမ်းမယ်', onPressed: _canSave ? _save : null),
          ],
        ),
      ),
    );
  }

  List<Widget> _imeiBody() => [
        Row(
          children: [
            Expanded(
              child: AppInput(
                key: const ValueKey('imei'),
                controller: _imei,
                hint: 'IMEI 15 လုံး (scan / ရိုက်)',
                keyboardType: TextInputType.number,
                semanticLabel: 'IMEI ထည့်ရန်',
                onSubmitted: (_) => _addImei(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: PrimaryButton(
                label: '+ ထည့်',
                variant: ButtonVariant.soft,
                height: 48,
                radius: 12,
                fontSize: 14,
                onPressed: _imei.text.trim().isEmpty ? null : _addImei,
              ),
            ),
          ],
        ),
        if (_imeis.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in _imeis)
                InputChip(
                  label: Text(i, style: AppText.s(12, weight: AppText.w600, color: AppColors.serialChipFg)),
                  backgroundColor: AppColors.serialChipBg,
                  deleteButtonTooltipMessage: 'ဖယ်ရန်',
                  onDeleted: () => setState(() => _imeis.remove(i)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text('IMEI ${_imeis.length} လုံး = Stock +${_imeis.length}', style: AppText.s(12, color: AppColors.muted)),
        const SizedBox(height: 10),
        NumericKeypad(
          onKey: _imeiKey,
          keyHeight: 44,
          keys: const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', NumericKeypad.backspace],
        ),
      ];

  List<Widget> _batchBody() {
    final isNew = _batch == ModuleRestockSheet.newBatch;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final b in _batches)
            _choice(
              key: ValueKey('restockBatch-${b.id}'),
              selected: _batch == b.id,
              label: [
                b.batchNo,
                if (b.expiryDate != null) _dates.format(b.expiryDate!),
                'ကျန် ${Qty.format(b.qtyMilli)}',
              ].join(' · '),
              expired: b.isExpired(_now),
              onTap: () => setState(() => _batch = b.id),
            ),
          _choice(
            key: const ValueKey('restockBatch-new'),
            selected: isNew,
            label: '+ Batch အသစ်',
            onTap: () => setState(() => _batch = ModuleRestockSheet.newBatch),
          ),
        ],
      ),
      if (isNew) ...[
        const SizedBox(height: 10),
        TwoCol(
          LabeledField(
            label: 'Batch နံပါတ်',
            small: true,
            child: AppInput(key: const ValueKey('restockBatchNo'), controller: _batchNo, semanticLabel: 'Batch နံပါတ်'),
          ),
          LabeledField(
            label: 'သက်တမ်းကုန်ရက်',
            small: true,
            child: Semantics(
              button: true,
              label: 'သက်တမ်းကုန်ရက်',
              child: InkWell(
                key: const ValueKey('restockExpiry'),
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
      ],
      const SizedBox(height: 12),
      QtyPad(decimal: widget.decimal, unit: widget.unit, onChanged: (m) => setState(() => _milli = m)),
    ];
  }

  List<Widget> _variantBody() => [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in widget.variants)
              _choice(
                key: ValueKey('restockVariant-${v.id}'),
                selected: _variant == v.id,
                label: '${v.label} · ကျန် ${Qty.format(widget.variantStock[v.id] ?? 0)}',
                onTap: () => setState(() => _variant = v.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        QtyPad(decimal: widget.decimal, unit: widget.unit, onChanged: (m) => setState(() => _milli = m)),
      ];

  Widget _choice({
    required Key key,
    required bool selected,
    required String label,
    required VoidCallback onTap,
    bool expired = false,
  }) =>
      Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.inputR,
            side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: 2),
          ),
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: AppRadius.inputR,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(label, style: AppText.s(13, weight: AppText.w600))),
                    if (expired) ...[const SizedBox(width: 6), const ExpiredBadge()],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Red "သက်တမ်းကုန်" mark for an expired batch.
class ExpiredBadge extends StatelessWidget {
  const ExpiredBadge({super.key});

  static const label = 'သက်တမ်းကုန်';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: const BoxDecoration(color: AppColors.dangerBg, borderRadius: AppRadius.chipR),
        child: Text(label, style: AppText.s(11, weight: AppText.w700, color: AppColors.danger)),
      );
}
