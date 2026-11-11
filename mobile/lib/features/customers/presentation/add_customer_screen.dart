import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../data/customer_providers.dart';
import '../domain/customer.dart';

class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  ConsumerState<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends ConsumerState<AddCustomerScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _limit = TextEditingController();
  final _opening = TextEditingController();
  final _note = TextEditingController();
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_showErrors) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _limit, _opening, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final t = nowUtc();
    final customer = Customer(
      id: newId(),
      tenantId: ref.read(tenantIdProvider),
      name: name,
      phone: _phone.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      creditLimit: int.tryParse(_limit.text),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: t,
      updatedAt: t,
    );
    ref.read(customersProvider.notifier).add(customer);
    // Opening balance from the paper book goes into the ledger.
    final opening = int.tryParse(_opening.text) ?? 0;
    if (opening != 0) {
      ref.read(debtLedgerProvider.notifier).adjustment(customer.id, opening, note: 'ယခင်အကြွေး');
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'ဖောက်သည်အသစ်',
            leadingIcon: AppIcons.close,
            leadingLabel: 'ပိတ်ရန်',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                FormSection(
                  gap: 14,
                  children: [
                    LabeledField(
                      label: 'အမည်',
                      required: true,
                      child: AppInput(
                        controller: _name,
                        hint: 'ဥပမာ - ဦးအောင်ကျော်',
                        semanticLabel: 'အမည်',
                        borderColor: _showErrors && _name.text.trim().isEmpty ? AppColors.danger : AppColors.inputBorder,
                      ),
                    ),
                    LabeledField(
                      label: 'ဖုန်းနံပါတ်',
                      helper: 'Viber နဲ့ အကြွေးသတိပေးစာ ပို့ဖို့ သုံးပါမယ်',
                      child: Row(
                        children: [
                          Expanded(
                            child: AppInput(
                              controller: _phone,
                              hint: '09 xxx xxx xxx',
                              keyboardType: TextInputType.phone,
                              semanticLabel: 'ဖုန်းနံပါတ်',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: 'Contacts ထဲက ရွေးရန်',
                            excludeSemantics: true,
                            child: Material(
                              color: AppColors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {},
                                child: const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(child: AppIcon(AppIcons.user, size: 20, color: AppColors.text)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    LabeledField(
                      label: 'လိပ်စာ',
                      child: AppInput(controller: _address, hint: 'ရပ်ကွက် / လမ်း', semanticLabel: 'လိပ်စာ'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FormSection(
                  title: 'အကြွေး',
                  gap: 14,
                  children: [
                    LabeledField(
                      label: 'အကြွေး ကန့်သတ်ချက် (Ks)',
                      helper: 'ဒီထက်ကျော်ရင် ရောင်းတဲ့အချိန် သတိပေးပါမယ်။ မထည့်ရင် ကန့်သတ်ချက်မရှိ',
                      child: AppInput(
                        controller: _limit,
                        hint: 'ဥပမာ - 100000',
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        semanticLabel: 'အကြွေး ကန့်သတ်ချက်',
                      ),
                    ),
                    LabeledField(
                      label: 'ယခင်အကြွေး (စာအုပ်ထဲက)',
                      child: AppInput(
                        controller: _opening,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        semanticLabel: 'ယခင်အကြွေး',
                      ),
                    ),
                    LabeledField(
                      label: 'မှတ်ချက်',
                      child: AppInput(
                        controller: _note,
                        maxLines: 2,
                        hint: 'ဥပမာ - လဆန်း ၅ ရက်မှ ဆပ်လေ့ရှိ',
                        semanticLabel: 'မှတ်ချက်',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          BottomActionBar(
            child: Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'မလုပ်တော့ပါ',
                    variant: ButtonVariant.outline,
                    borderColor: AppColors.inputBorder,
                    height: 54,
                    radius: 14,
                    fontSize: 15,
                    onPressed: () => context.pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(label: 'သိမ်းမယ်', height: 54, radius: 14, fontSize: 15, onPressed: _save),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
