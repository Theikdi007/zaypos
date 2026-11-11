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
import '../../customers/data/customer_providers.dart';
import '../../customers/domain/customer_account.dart';
import '../../customers/presentation/widgets/customer_row.dart';
import '../../inventory/data/stock_providers.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../sales/data/sales_providers.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_ui.dart';
import '../domain/cart.dart';

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

  void _confirm(Cart cart, CustomerAccount? customer) {
    final isDebt = _method == PaymentMethod.debt;
    final sale = ref.read(salesProvider.notifier).create(
          method: _method,
          lines: cart.toDrafts(),
          customerId: isDebt ? customer?.id : null,
          customerName: isDebt ? customer?.name : null,
          received: _method == PaymentMethod.cash && _received.text.isNotEmpty ? parseMoney(_received.text) : null,
        );
    final stock = ref.read(stockLedgerProvider.notifier);
    stock.record(stock.forSale(sale, StockMovementType.sale, sign: -1));
    if (isDebt && customer != null) {
      ref.read(debtLedgerProvider.notifier).creditSale(customer.id, sale);
    }
    ref.read(cartProvider.notifier).clear();
    context.go(Routes.receipt(sale.id));
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final customers = ref.watch(customerAccountsProvider);
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
                  onPressed: cart.isEmpty || blockReason != null ? null : () => _confirm(cart, customer),
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
                _stepBtn('−', 'လျှော့ရန်', () => cart.setQty(line.key, line.qtyMilli - CartNotifier.step)),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 22),
                  child: Text(Qty.format(line.qtyMilli), textAlign: TextAlign.center, style: AppText.s(15, weight: AppText.w700)),
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
