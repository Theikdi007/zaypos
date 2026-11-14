import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/qty.dart';
import '../../../core/utils/thousands_formatter.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/qty_sheet.dart';
import '../../../core/features/features_providers.dart';
import '../../customers/data/customer_providers.dart';
import '../../customers/domain/customer_account.dart';
import '../../customers/presentation/widgets/customer_row.dart';
import '../../sales/application/checkout_service.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_ui.dart';
import '../domain/cart.dart';

/// Warning when a credit sale of [saleTotal] takes [c] over their credit
/// limit — the same rule the server flags later (balance > limit). It warns,
/// it does not block: the owner decides. Null = no limit, or still within it.
String? creditLimitWarning(CustomerAccount c, int saleTotal) {
  final limit = c.customer.creditLimit;
  if (limit == null) return null;
  final after = c.balance + saleTotal;
  if (after <= limit) return null;
  return 'အကြွေး ကန့်သတ်ချက် ${formatKs(limit)} ကျော်ပါမယ် · ရောင်းပြီးရင် ${formatKs(after)}';
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod _method = PaymentMethod.cash;
  final _received = TextEditingController();
  String? _customerId;

  @override
  void initState() {
    super.initState();
    _received.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  /// The explicitly chosen customer — never defaulted, so a credit sale
  /// can't silently land on the wrong account.
  CustomerAccount? _customer(List<CustomerAccount> all) {
    for (final c in all) {
      if (c.id == _customerId) return c;
    }
    return null;
  }

  /// Why confirming is blocked (shown under the button), or null if allowed.
  /// (Going over a credit limit only warns — see [creditLimitWarning].)
  String? _blockReason(Cart cart, CustomerAccount? customer) {
    if (cart.isEmpty) return null; // nothing to hint; button just disabled
    if (_method == PaymentMethod.debt && customer == null) return 'အကြွေးရောင်းရန် ဖောက်သည် ရွေးပါ';
    if (_method == PaymentMethod.cash && _received.text.isNotEmpty && parseMoney(_received.text) < cart.total) {
      return 'လက်ခံရရှိငွေ စုစုပေါင်းထက် နည်းနေပါသည်';
    }
    return null;
  }

  Future<void> _pickCustomer(List<CustomerAccount> all) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    DividedColumn(children: [
                      for (final c in all) CustomerRow(account: c, onTap: () => Navigator.pop(ctx, c.id)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _customerId = picked);
  }

  bool _submitting = false;

  Future<void> _confirm(Cart cart, CustomerAccount? customer) async {
    setState(() => _submitting = true);
    try {
      final sale = await ref.read(checkoutServiceProvider).checkout(CheckoutRequest(
            lines: cart.toDrafts(),
            method: _method,
            customerId: _method == PaymentMethod.debt ? customer?.id : null,
            received: _method == PaymentMethod.cash && _received.text.isNotEmpty ? parseMoney(_received.text) : null,
          ));
      ref.read(cartProvider.notifier).clear();
      if (mounted) context.go(Routes.receipt(sale.id));
    } on CheckoutException {
      // The button is disabled for these cases; nothing was stored.
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final customers = ref.watch(customerAccountsProvider).value ?? const [];
    final customer = _customer(customers);
    final received = parseMoney(_received.text);
    final change = received > cart.total ? received - cart.total : 0;
    final blockReason = _blockReason(cart, customer);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'ငွေရှင်းမယ်', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              children: [
                AppCard(
                  child: DividedColumn(children: [
                    for (final l in cart.lines) _LineRow(line: l),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('လျှော့ဈေး', style: AppText.s(14, color: AppColors.muted)),
                          Text('0 Ks', style: AppText.s(14, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SectionTitle('ငွေပေးချေမှု'),
                Padding(
                  padding: AppSpacing.pagePadding,
                  child: Column(
                    children: [
                      for (var i = 0; i < PaymentMethod.values.length; i += 2) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _methodButton(PaymentMethod.values[i])),
                          const SizedBox(width: 10),
                          Expanded(child: _methodButton(PaymentMethod.values[i + 1])),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                switch (_method) {
                  PaymentMethod.cash => AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LabeledField(
                            label: 'လက်ခံရရှိငွေ',
                            small: true,
                            child: AppInput(
                              controller: _received,
                              fontSize: 18,
                              fontWeight: AppText.w700,
                              keyboardType: TextInputType.number,
                              inputFormatters: [ThousandsFormatter()],
                              semanticLabel: 'လက်ခံရရှိငွေ',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ပြန်အမ်းရန်', style: AppText.s(14, color: AppColors.muted)),
                              MoneyText(change, size: 14, color: AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  PaymentMethod.debt => customer == null
                      ? AppCard(
                          padding: const EdgeInsets.all(14),
                          color: AppColors.debtBg,
                          borderColor: AppColors.debtBorder,
                          child: InkWell(
                            onTap: () => _pickCustomer(customers),
                            child: Row(
                              children: [
                                const InitialAvatar(
                                    initial: '?', bg: AppColors.debtAvatar, fg: AppColors.debtInk, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('ဖောက်သည် ရွေးပါ',
                                      style: AppText.s(14, weight: AppText.w700)),
                                ),
                                Text('ရွေးရန်',
                                    style: AppText.s(13, weight: AppText.w600, color: AppColors.debtInk)),
                              ],
                            ),
                          ),
                        )
                      : AppCard(
                          padding: const EdgeInsets.all(14),
                          color: AppColors.debtBg,
                          borderColor: AppColors.debtBorder,
                          child: Row(
                            children: [
                              InitialAvatar(
                                  initial: customer.initial,
                                  bg: AppColors.debtAvatar,
                                  fg: AppColors.debtInk,
                                  size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(customer.name, style: AppText.s(14, weight: AppText.w700)),
                                    Text('ယခင်အကြွေး ${formatKs(customer.balance)}',
                                        style: AppText.s(12, color: AppColors.debtInk)),
                                    if (creditLimitWarning(customer, cart.total) case final w?)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Text(w,
                                              key: const ValueKey('creditLimitWarning'),
                                              style: AppText.s(12, weight: AppText.w700, color: AppColors.danger)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => _pickCustomer(customers),
                                child: Text('ပြောင်းရန်',
                                    style: AppText.s(13, weight: AppText.w600, color: AppColors.debtInk)),
                              ),
                            ],
                          ),
                        ),
                  _ => AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('ငွေလွှဲ screenshot (မဖြစ်မနေ မဟုတ်ပါ)',
                              style: AppText.s(13, weight: AppText.w600, color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {},
                            borderRadius: AppRadius.inputR,
                            child: DashedBox(
                              background: AppColors.fillSoft,
                              child: SizedBox(
                                height: 48,
                                child: Center(
                                  child: Text('+ ဓာတ်ပုံ ထည့်မယ်',
                                      style: AppText.s(14, color: AppColors.textSecondary)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                },
              ],
            ),
          ),
          BottomActionBar(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('စုစုပေါင်း', style: AppText.s(15, color: AppColors.textSecondary)),
                    MoneyText(cart.total, size: 26),
                  ],
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'အတည်ပြုပြီး ပြေစာထုတ်မယ်',
                  dimWhenDisabled: blockReason != null,
                  onPressed: cart.isEmpty || blockReason != null || _submitting ? null : () => _confirm(cart, customer),
                ),
                if (blockReason != null) ...[
                  const SizedBox(height: 8),
                  Text(blockReason,
                      textAlign: TextAlign.center, style: AppText.s(12, weight: AppText.w600, color: AppColors.danger)),
                ],
              ],
            ),
          ),
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
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _method = m),
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(m.label, style: AppText.s(14, weight: AppText.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    final decimal = ref.watch(tenantFeaturesProvider).decimalQty;
    // Tap the quantity: type it (decimals when decimalQty is on, e.g. 2.5 ပေ).
    Future<void> editQty() async {
      final q = await showQtySheet(
        context,
        title: 'အရေအတွက်',
        subtitle: '${line.name} · ${formatKs(line.price)}',
        decimal: decimal,
        initialMilli: line.qtyMilli,
        confirmLabel: 'ပြောင်းမယ်',
      );
      if (q != null) cart.setQty(line.key, q);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: AppText.s(14, weight: AppText.w600)),
                Text(formatKs(line.price), style: AppText.s(12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: AppColors.fill, borderRadius: AppRadius.inputR),
            child: Row(
              children: [
                _stepBtn('−', 'လျှော့ရန်', () {
                  // Never below what is there when it is one unit or less (0.5 stays 0.5).
                  if (line.qtyMilli > CartNotifier.step) cart.setQty(line.key, line.qtyMilli - CartNotifier.step);
                }),
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  label: 'အရေအတွက် ${Qty.format(line.qtyMilli)} · ပြောင်းရန်',
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('qty-${line.key}'),
                    onTap: editQty,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
                      child: Center(
                        child: Text(Qty.format(line.qtyMilli),
                            textAlign: TextAlign.center,
                            style: AppText.s(15, weight: AppText.w700)
                                .copyWith(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _stepBtn('+', 'တိုးရန်', () => cart.setQty(line.key, line.qtyMilli + CartNotifier.step)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: MoneyText(line.total, showUnit: false, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(String label, String semantic, VoidCallback onTap) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: Text(label, style: AppText.s(18, weight: AppText.w700, height: 1.2))),
          ),
        ),
      );
}
