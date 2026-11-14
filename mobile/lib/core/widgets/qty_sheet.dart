import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/qty.dart';
import 'numeric_keypad.dart';
import 'primary_button.dart';

/// Quantity entry on a keypad. With [decimal] (TenantFeatures.decimalQty) the
/// keypad has a "." key and accepts up to 3 decimal places (2.5 ပေ, 0.75 ကီလို);
/// otherwise whole units only. Returns milli-units (> 0), or null if dismissed.
Future<int?> showQtySheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool decimal,
  int? initialMilli,
  String unit = 'ခု',
  String confirmLabel = 'သိမ်းမယ်',
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => QtySheet(
        title: title,
        subtitle: subtitle,
        decimal: decimal,
        initialMilli: initialMilli,
        unit: unit,
        confirmLabel: confirmLabel,
      ),
    );

class QtySheet extends StatefulWidget {
  const QtySheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.decimal,
    this.initialMilli,
    this.unit = 'ခု',
    this.confirmLabel = 'သိမ်းမယ်',
  });

  final String title;
  final String subtitle;
  final bool decimal;
  final int? initialMilli;
  final String unit;
  final String confirmLabel;

  static const decimalPoint = '.';

  @override
  State<QtySheet> createState() => _QtySheetState();
}

class _QtySheetState extends State<QtySheet> {
  late int _milli = widget.initialMilli ?? 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.title, style: AppText.s(18, weight: AppText.w700)),
            ),
            const SizedBox(height: 2),
            Text(widget.subtitle, style: AppText.s(13, color: AppColors.muted)),
            const SizedBox(height: 12),
            QtyPad(
              decimal: widget.decimal,
              initialMilli: widget.initialMilli,
              unit: widget.unit,
              onChanged: (m) => setState(() => _milli = m),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: widget.confirmLabel,
              onPressed: _milli > 0 ? () => Navigator.pop(context, _milli) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The quantity display + keypad of [QtySheet], reusable inside other sheets
/// (e.g. "Stock ဖြည့်မယ်" for a batch or size/colour). Reports milli-units
/// (0 = nothing / invalid yet) through [onChanged].
class QtyPad extends StatefulWidget {
  const QtyPad({
    super.key,
    required this.decimal,
    required this.onChanged,
    this.initialMilli,
    this.unit = 'ခု',
  });

  final bool decimal;
  final int? initialMilli;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  State<QtyPad> createState() => _QtyPadState();
}

class _QtyPadState extends State<QtyPad> {
  /// What the user typed, e.g. "2.5". Empty = nothing yet.
  late String _text = widget.initialMilli == null || widget.initialMilli! <= 0
      ? ''
      : Qty.format(widget.initialMilli!);

  /// Prefilled value is replaced by the first key press.
  late bool _fresh = _text.isNotEmpty;

  int get _milli => Qty.parse(_text, decimal: widget.decimal) ?? 0;

  void _onKey(String v) {
    setState(() {
      if (_fresh) {
        _fresh = false;
        if (v != NumericKeypad.backspace) _text = '';
      }
      if (v == NumericKeypad.backspace) {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
        return;
      }
      if (v == QtySheet.decimalPoint) {
        if (!widget.decimal || _text.contains('.')) return;
        _text = _text.isEmpty ? '0.' : '$_text.';
        return;
      }
      final dot = _text.indexOf('.');
      if (dot >= 0 && _text.length - dot - 1 + v.length > 3) return; // max 3 dp
      if (dot < 0 && _text.length + v.length > 6) return; // max 999,999 units
      if (_text.isEmpty && (v == '0' || v == '00')) {
        if (widget.decimal && v == '0') _text = '0';
        return;
      }
      if (_text == '0' && dot < 0) _text = '';
      _text += v;
    });
    widget.onChanged(_milli);
  }

  @override
  Widget build(BuildContext context) {
    final keys = [
      '1', '2', '3', '4', '5', '6', '7', '8', '9', //
      widget.decimal ? QtySheet.decimalPoint : '00', '0', NumericKeypad.backspace,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text('${_text.isEmpty ? '0' : _text} ${widget.unit}',
              key: const ValueKey('qtySheetValue'),
              textAlign: TextAlign.right,
              style: AppText.s(32, weight: AppText.w700)),
        ),
        if (widget.decimal)
          Text('ဒသမ ရနိုင်သည် (ဥပမာ 2.5)', textAlign: TextAlign.right, style: AppText.s(12, color: AppColors.success)),
        const SizedBox(height: 10),
        NumericKeypad(onKey: _onKey, keys: keys),
      ],
    );
  }
}
