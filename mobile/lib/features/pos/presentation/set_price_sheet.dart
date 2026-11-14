import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/primary_button.dart';

/// Asks for the selling price of a product that has none (price 0), so it is
/// never sold at 0 Ks. Returns the price (kyats), or null if dismissed.
Future<int?> showSetPriceSheet(BuildContext context, {required String productName}) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SetPriceSheet(productName: productName),
    );

class _SetPriceSheet extends StatefulWidget {
  const _SetPriceSheet({required this.productName});
  final String productName;

  @override
  State<_SetPriceSheet> createState() => _SetPriceSheetState();
}

class _SetPriceSheetState extends State<_SetPriceSheet> {
  String _amount = '';

  int get _price => int.tryParse(_amount) ?? 0;

  void _onKey(String v) => setState(() {
        if (v == NumericKeypad.backspace) {
          if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
        } else if (_amount.length < 9) {
          if (_amount.isEmpty && (v == '0' || v == '00')) return;
          _amount += v;
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
              child: Text('ဈေးနှုန်း ထည့်ပါ', style: AppText.s(18, weight: AppText.w700)),
            ),
            const SizedBox(height: 2),
            Text('${widget.productName} · ဈေးနှုန်း မထည့်ရသေးပါ။ ထည့်လိုက်ရင် ပစ္စည်းမှာ သိမ်းပြီး ဒီအရောင်းမှာ သုံးပါမယ်။',
                style: AppText.s(13, color: AppColors.muted)),
            const SizedBox(height: 12),
            MoneyText(_price, size: 32, unitSize: 16, unitColor: AppColors.muted, textAlign: TextAlign.right),
            const SizedBox(height: 10),
            NumericKeypad(onKey: _onKey),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'သိမ်းပြီး ခြင်းထဲထည့်မယ်',
              onPressed: _price > 0 ? () => Navigator.pop(context, _price) : null,
            ),
          ],
        ),
      ),
    );
  }
}
