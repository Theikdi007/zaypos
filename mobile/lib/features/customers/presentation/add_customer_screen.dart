import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/sync_limits.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/utils/ids.dart';
import '../../auth/data/session.dart';
import '../application/customer_service.dart';
import '../data/customer_providers.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';

/// Add Customer, or — with [customerId] — edit that customer (BUG-33: "ပြင်ဆင်ရန်" on the debt screen).
/// Same fields and rules; edit mode has no opening balance (that is a ledger entry) and shows the
/// current balance next to the credit limit (a limit below it is allowed).
class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key, this.customerId});
  final String? customerId;

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

  /// The customer being edited (null = new, or not loaded yet).
  Customer? _editing;
  bool get _isEdit => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_showErrors) setState(() {});
    });
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    final c = await ref.read(customerRepositoryProvider).watchById(widget.customerId!).first;
    if (!mounted || c == null) return;
    setState(() {
      _editing = c;
      _name.text = c.name;
      _phone.text = c.phone;
      _address.text = c.address ?? '';
      _limit.text = c.creditLimit?.toString() ?? '';
      _note.text = c.note ?? '';
    });
  }

  /// Another live customer already has this phone number: warn, don't block (same as the barcode warning).
  Future<bool> _confirmDuplicatePhone(String phone) async {
    final others = (ref.read(customersProvider).value ?? await ref.read(customerRepositoryProvider).watchAll().first)
        .where((o) => o.id != widget.customerId && samePhone(o.phone, phone))
        .toList();
    if (others.isEmpty || !mounted) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ', style: AppText.s(16, weight: AppText.w700)),
            content: Text(
              '$phone ကို ${others.map((o) => '“${o.name}”').join('၊ ')} မှာ သုံးထားပြီးပါပြီ။ ဒီအတိုင်း သိမ်းမလား?',
              style: AppText.s(14),
            ),
            actions: [
              TextButton(
                key: const ValueKey('duplicatePhoneCancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ပြန်ပြင်မယ်'),
              ),
              TextButton(
                key: const ValueKey('duplicatePhoneSave'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('ဒီအတိုင်း သိမ်းမယ်', style: AppText.s(14, weight: AppText.w700)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _limit, _opening, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Field → message, from the server's rules (/sync/limits).
  Map<String, String> _errors = {};

  Future<void> _save() async {
    final limits = ref.read(syncLimitsProvider);
    final name = _name.text.trim();
    // Stored as the server will store it (Myanmar digits → 0-9, other non-ASCII dropped).
    final phone = limits.normalize('customers.phone', _phone.text);
    final address = _address.text.trim();
    final note = _note.text.trim();
    final errors = <String, String>{
      for (final (key, error) in [
        ('name', limits.checkText('customers.name', name, label: 'အမည်')),
        ('phone', limits.checkText('customers.phone', phone.isEmpty ? null : phone, label: 'ဖုန်းနံပါတ်')),
        ('address', limits.checkText('customers.address', address.isEmpty ? null : address, label: 'လိပ်စာ')),
        ('note', limits.checkText('customers.note', note.isEmpty ? null : note, label: 'မှတ်ချက်')),
        ('limit', limits.checkNumber('customers.creditLimit', int.tryParse(_limit.text), label: 'အကြွေး ကန့်သတ်ချက်')),
      ])
        key: ?error,
    };
    if (name.isEmpty) errors['name'] ??= 'အမည် ထည့်ပါ။';
    if (errors.isNotEmpty) {
      setState(() {
        _showErrors = true;
        _errors = errors;
      });
      return;
    }
    final editing = _editing;
    if (_isEdit && editing == null) return; // not loaded yet
    if (phone.isNotEmpty && !samePhone(phone, editing?.phone) && !await _confirmDuplicatePhone(phone)) return;
    if (!mounted) return;
    if (editing != null) {
      await ref.read(customerServiceProvider).update(editing.copyWith(
            name: name,
            phone: phone,
            address: () => address.isEmpty ? null : address,
            creditLimit: () => int.tryParse(_limit.text),
            note: () => note.isEmpty ? null : note,
          ));
      if (mounted) context.pop();
      return;
    }
    final t = nowUtc();
    final customer = Customer(
      id: newId(),
      tenantId: ref.read(tenantIdProvider),
      name: name,
      phone: phone,
      address: address.isEmpty ? null : address,
      creditLimit: int.tryParse(_limit.text),
      note: note.isEmpty ? null : note,
      createdAt: t,
      updatedAt: t,
    );
    // Opening balance from the paper book goes into the ledger (same unit of work).
    await ref.read(customerServiceProvider).create(customer, openingBalance: int.tryParse(_opening.text) ?? 0);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final balance = _isEdit ? ref.watch(customerAccountProvider(widget.customerId!)).value?.balance : null;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: _isEdit ? 'ဖောက်သည် ပြင်ဆင်ရန်' : 'ဖောက်သည်အသစ်',
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
                      error: _errors['name'],
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
                      error: _errors['phone'],
                      // The contact picker ("ဖုန်းစာအုပ်ထဲက ရွေးရန်") is hidden for the beta (BUG-46, beta backlog).
                      child: AppInput(
                        controller: _phone,
                        hint: '09 xxx xxx xxx',
                        keyboardType: TextInputType.phone,
                        semanticLabel: 'ဖုန်းနံပါတ်',
                      ),
                    ),
                    LabeledField(
                      label: 'လိပ်စာ',
                      error: _errors['address'],
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
                      error: _errors['limit'],
                      child: Row(
                        children: [
                          Expanded(
                            child: AppInput(
                              controller: _limit,
                              hint: 'ဥပမာ - 100000',
                              keyboardType: TextInputType.number,
                              inputFormatters: digits,
                              semanticLabel: 'အကြွေး ကန့်သတ်ချက်',
                            ),
                          ),
                          // Edit: the current balance next to the limit (a lower limit is allowed).
                          if (balance != null) ...[
                            const SizedBox(width: 10),
                            Column(
                              key: const ValueKey('currentBalance'),
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('လက်ရှိ အကြွေး', style: AppText.s(12, color: AppColors.muted)),
                                Text(formatKs(balance), style: AppText.s(14, weight: AppText.w700)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!_isEdit)
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
                      error: _errors['note'],
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
