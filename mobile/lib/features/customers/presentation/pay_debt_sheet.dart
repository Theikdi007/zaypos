import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../sales/domain/sale.dart';
import '../application/customer_service.dart';
import '../domain/customer_account.dart';

/// Opens the "ငွေပြန်ဆပ်" modal bottom sheet for [customer].
Future<void> showPayDebtSheet(BuildContext context, CustomerAccount customer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PayDebtSheet(customer: customer),
  );
}

class PayDebtSheet extends ConsumerStatefulWidget {
  const PayDebtSheet({super.key, required this.customer});

  final CustomerAccount customer;

  @override
  ConsumerState<PayDebtSheet> createState() => _PayDebtSheetState();
}

class _PayDebtSheetState extends ConsumerState<PayDebtSheet> {
  final _amount = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  static const _methods = [PaymentMethod.cash, PaymentMethod.kbz, PaymentMethod.wave];

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _setAmount(int v) {
    _amount.text = '$v';
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
  }

  /// True while the payment is being written: a second tap does nothing
  /// (one tap = one payment, like Checkout).
  bool _busy = false;

  Future<void> _confirm(int amount) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (amount > 0) {
        await ref.read(customerServiceProvider).recordPayment(
              tenantId: widget.customer.customer.tenantId,
              customerId: widget.customer.id,
              amount: amount,
              method: _method,
            );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final owed = c.balance;
    final a = int.tryParse(_amount.text) ?? 0;
    final rem = owed - a;
    final (remText, remBg, remFg) = rem < 0
        ? ('ပိုပေးထား ${formatKs(-rem)}', AppColors.dangerBg, AppColors.danger)
        : rem == 0
            ? ('ရှင်းပြီ', AppColors.successBg, AppColors.success)
            : (formatKs(rem), AppColors.debtBg, AppColors.debtInk);
    final insets = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(padding: EdgeInsets.zero),
          const SizedBox(height: 16),
          Row(
            children: [
              InitialAvatar(initial: c.initial, bg: AppColors.debtAvatar, fg: AppColors.debtInk, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('ငွေပြန်ဆပ် · ${c.name}', style: AppText.s(17, weight: AppText.w700)),
                    ),
                    Text('ပေးရန်ကျန် ${formatKs(owed)}', style: AppText.s(13, color: AppColors.debtInk)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'ဆပ်မယ့်ပမာဏ (Ks)',
            child: AppInput(
              controller: _amount,
              height: 56,
              radius: 14,
              horizontalPadding: 14,
              fontSize: 22,
              fontWeight: AppText.w700,
              borderColor: AppColors.primary,
              borderWidth: 2,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              semanticLabel: 'ဆပ်မယ့်ပမာဏ',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, q) in [(10000, '10,000'), (20000, '20,000'), (owed, 'အကုန်ဆပ်')].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: AppColors.fillSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.inputR,
                      side: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    child: InkWell(
                      borderRadius: AppRadius.inputR,
                      onTap: () => _setAmount(q.$1),
                      child: SizedBox(
                        height: 40,
                        child: Center(child: Text(q.$2, style: AppText.s(13, weight: AppText.w600))),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text('ငွေပေးချေမှု', style: AppText.s(14, weight: AppText.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, m) in _methods.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _methodButton(m)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: remBg, borderRadius: AppRadius.inputR),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ဆပ်ပြီးရင် ကျန်မယ့်ငွေ', style: AppText.s(14, weight: AppText.w600, color: remFg)),
                Text(remText, style: AppText.s(14, weight: AppText.w600, color: remFg)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: '${formatKs(a)} လက်ခံမယ်', onPressed: _busy ? null : () => _confirm(a)),
        ],
      ),
    );
  }

  Widget _methodButton(PaymentMethod m) {
    final on = m == _method;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.inputR,
          side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: 2),
        ),
        child: InkWell(
          borderRadius: AppRadius.inputR,
          onTap: () => setState(() => _method = m),
          child: SizedBox(
            height: 48,
            child: Center(child: Text(m.label, style: AppText.s(14, weight: AppText.w700))),
          ),
        ),
      ),
    );
  }
}
