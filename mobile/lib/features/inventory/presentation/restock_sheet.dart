import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/primary_button.dart';

/// "Stock ဖြည့်မယ်": goods received for one product, in whole units.
/// Returns the quantity (milli-units), or null if dismissed. For an
/// [untracked] product this is its first count, which starts tracking it.
Future<int?> showRestockSheet(BuildContext context, {required String productName, required bool untracked}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RestockSheet(productName: productName, untracked: untracked),
    );

class _RestockSheet extends StatefulWidget {
  const _RestockSheet({required this.productName, required this.untracked});
  final String productName;
  final bool untracked;

  @override
  State<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<_RestockSheet> {
  String _digits = '';

  int get _units => int.tryParse(_digits) ?? 0;

  void _onKey(String v) => setState(() {
        if (v == NumericKeypad.backspace) {
          if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
        } else if (_digits.length < 6) {
          if (_digits.isEmpty && (v == '0' || v == '00')) return;
          _digits += v;
        }
      });

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
              child: Text('Stock ဖြည့်မယ်', style: AppText.s(18, weight: AppText.w700)),
            ),
            const SizedBox(height: 2),
            Text(
              widget.untracked
                  ? '${widget.productName} · Stock မမှတ်ရသေးပါ။ လက်ရှိ ရှိနေတဲ့ အရေအတွက် ထည့်လိုက်ရင် စမှတ်ပါမယ်။'
                  : '${widget.productName} · ဝင်လာတဲ့ အရေအတွက် ထည့်ပါ။',
              style: AppText.s(13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Text('$_units ခု',
                textAlign: TextAlign.right, style: AppText.s(32, weight: AppText.w700)),
            const SizedBox(height: 10),
            NumericKeypad(onKey: _onKey),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'သိမ်းမယ်',
              onPressed: _units > 0 ? () => Navigator.pop(context, Qty.units(_units)) : null,
            ),
          ],
        ),
      ),
    );
  }
}
