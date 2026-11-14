import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/numeric_keypad.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/product_tile.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../products/application/product_service.dart';
import '../../products/data/product_providers.dart';
import '../../products/domain/product_view.dart';
import '../../../core/sync/sync_limits.dart';
import '../../scan/barcode_scanner.dart';
import 'module_pick_sheet.dart';
import 'set_price_sheet.dart';
import '../../devices/data/device_providers.dart';
import '../domain/cart.dart';
import '../../../core/widgets/async_view.dart';

enum PosMode { products, quick }

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  PosMode? _mode;
  String? _cat; // null = all
  String _query = '';
  String _amount = '';
  final _quickName = TextEditingController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _quickName.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _scanWithCamera() async {
    final code = await ref.read(barcodeScannerProvider).scan(context, title: 'Barcode scan');
    if (code != null && mounted) await _onScan(code);
  }

  /// A scanned barcode (camera or a HID scanner): the product goes into the
  /// cart like a tap; an unknown code offers "ပစ္စည်းအသစ် ထည့်မယ်" with it.
  Future<void> _onScan(String raw) async {
    // Only when POS is on top (not under Checkout / a sheet).
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    // A HID scanner also types into a focused search box: undo that.
    if (_search.text.isNotEmpty && _search.text.contains(raw.trim())) {
      _search.clear();
      setState(() => _query = '');
    }
    final limits = ref.read(syncLimitsProvider);
    final code = limits.normalize('products.barcode', raw);
    final p = productByBarcode(ref.read(productsProvider).value ?? const [], code, limits);
    if (p != null) {
      await _addProduct(p);
      return;
    }
    final add = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ', style: AppText.s(17, weight: AppText.w700)),
              const SizedBox(height: 4),
              Text(code, key: const ValueKey('unknownBarcode'), style: AppText.s(15, color: AppColors.muted)),
              const SizedBox(height: 16),
              PrimaryButton(label: 'ပစ္စည်းအသစ် ထည့်မယ်', onPressed: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'မလုပ်တော့ပါ',
                variant: ButtonVariant.outline,
                borderColor: AppColors.inputBorder,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (add == true && mounted) await context.push(Routes.addProductWithBarcode(code));
  }

  void _onKey(String v) {
    setState(() {
      if (v == NumericKeypad.backspace) {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (_amount.length < 9) {
        if (_amount.isEmpty && (v == '0' || v == '00')) return;
        _amount += v;
      }
    });
  }

  /// A product without a price is never sold at 0 Ks: ask for the price, save
  /// it to the product (upsertProduct unit) and use it for this sale.
  Future<void> _addProduct(ProductView p) async {
    var product = p.product;
    if (p.needsPrice) {
      final price = await showSetPriceSheet(context, productName: p.name);
      if (price == null || !mounted) return;
      await ref.read(productServiceProvider).setPrice(p.id, price);
      product = product.copyWith(price: price);
    }
    if (!mounted) return;
    // Which IMEI / size-colour / batch (BUG-2).
    final result = await pickModuleUnit(context, ref, product, ref.read(cartProvider));
    switch (result) {
      case PickCancelled():
        return;
      case PlainProduct():
        ref.read(cartProvider.notifier).addProduct(product);
      case Picked(:final pick):
        ref.read(cartProvider.notifier).addProduct(product, pick: pick);
    }
  }

  void _addQuick() {
    final n = int.tryParse(_amount) ?? 0;
    if (n <= 0) return;
    ref.read(cartProvider.notifier).addQuick(n, _quickName.text);
    _quickName.clear();
    setState(() => _amount = '');
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(tenantFeaturesProvider);
    final cart = ref.watch(cartProvider);
    final nextNo = ref.watch(deviceProvider).value?.nextReceiptNo ?? '';
    final mode = features.quickSale ? (_mode ?? PosMode.quick) : PosMode.products;

    return Scaffold(
      body: HidScannerListener(
        onScan: _onScan,
        child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'ရောင်းမယ်',
                onBack: () => context.canPop() ? context.pop() : context.go(Routes.dashboard),
                trailing: Text('#$nextNo', style: AppText.s(13, color: AppColors.muted)),
                bottom: [
                  if (features.quickSale)
                    SegmentedTabs<PosMode>(
                      options: const [(PosMode.products, 'ပစ္စည်းများ'), (PosMode.quick, 'Quick Sale')],
                      selected: mode,
                      onChanged: (m) => setState(() => _mode = m),
                    ),
                  if (mode == PosMode.products) ..._productFilters(),
                ],
              ),
              Expanded(child: mode == PosMode.products ? _productGrid(cart) : _quickSale(cart)),
            ],
          ),
          Positioned(left: 12, right: 12, bottom: 16 + MediaQuery.paddingOf(context).bottom, child: _CartBar(cart: cart)),
        ],
        ),
      ),
    );
  }

  List<Widget> _productFilters() {
    final products = ref.watch(productsProvider).value ?? const [];
    final cats = <String>[];
    for (final p in products) {
      if (!cats.contains(p.category)) cats.add(p.category);
    }
    return [
      Row(
        children: [
          Expanded(
            child: SearchField(
              controller: _search,
              hint: 'ပစ္စည်းအမည် ရှာရန်',
              semanticLabel: 'ပစ္စည်းရှာရန်',
              onChanged: (q) => setState(() => _query = q.trim()),
            ),
          ),
          const SizedBox(width: 10),
          _ScanButton(onTap: _scanWithCamera),
        ],
      ),
      FilterChips<String?>(
        scrollable: true,
        options: [(null, 'အားလုံး'), for (final c in cats) (c, c)],
        selected: _cat,
        onChanged: (c) => setState(() => _cat = c),
      ),
    ];
  }

  Widget _productGrid(Cart cart) {
    final features = ref.watch(tenantFeaturesProvider);
    final async = ref.watch(productsProvider);
    if (!async.hasValue) return AsyncView(value: async, data: (_) => const SizedBox());
    final items = async.requireValue
        .where((p) => _cat == null || p.category == _cat)
        .where((p) => _query.isEmpty || p.name.contains(_query))
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 160,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final p = items[i];
        final low = !p.isUntracked && p.stockMilli <= Qty.units(3);
        final stockLabel = !features.stock
            ? null
            : p.isUntracked
                // No room beside the price badge on a tile; the badge wins.
                ? (p.needsPrice ? null : untrackedStockLabel)
                : low
                    ? 'ကျန် ${Qty.format(p.stockMilli)} ခု'
                    : 'Stock ${Qty.format(p.stockMilli)}';
        return ProductTile(
          name: p.name,
          initial: p.initial,
          tint: Color(p.tint),
          price: p.price,
          stockLabel: stockLabel,
          stockLow: low,
          qtyMilli: cart.qtyOfProduct(p.id),
          needsPrice: p.needsPrice,
          onTap: () => _addProduct(p),
        );
      },
    );
  }

  Widget _quickSale(Cart cart) {
    final quick = cart.quickLines;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ဈေးနှုန်း', style: AppText.s(12, color: AppColors.muted)),
              const SizedBox(height: 6),
              MoneyText(
                _amount.isEmpty ? 0 : int.parse(_amount),
                size: 36,
                letterSpacing: -0.5,
                unitSize: 16,
                unitColor: AppColors.muted,
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 6),
              Text('ပစ္စည်းအမည် (မထည့်လည်းရ)', style: AppText.s(12, color: AppColors.muted)),
              const SizedBox(height: 6),
              AppInput(
                controller: _quickName,
                height: 40,
                radius: 10,
                fontSize: 14,
                horizontalPadding: 10,
                borderColor: AppColors.border,
                hint: 'ဥပမာ - ဆပ်ပြာ',
                semanticLabel: 'ပစ္စည်းအမည်',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        NumericKeypad(onKey: _onKey),
        const SizedBox(height: 10),
        PrimaryButton(
          label: '+ ခြင်းထဲထည့်မယ်',
          variant: ButtonVariant.soft,
          height: 48,
          radius: 14,
          fontSize: 15,
          borderWidth: 2,
          onPressed: _addQuick,
        ),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('ထည့်ပြီး: ${quick.map((l) => formatMoney(l.price)).join(' + ')} Ks',
              style: AppText.s(12, color: AppColors.muted)),
        ],
      ],
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Barcode scan',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('posScan'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(child: AppIcon(AppIcons.barcode, color: AppColors.surface)),
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ပစ္စည်း ${Qty.format(cart.countMilli)} ခု',
                    style: AppText.s(12, color: AppColors.surface.withValues(alpha: 0.8))),
                MoneyText(cart.total, size: 20, color: AppColors.surface),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PrimaryButton(
            label: 'ငွေရှင်းမယ်',
            height: 52,
            radius: 14,
            fontSize: 15,
            horizontalPadding: 20,
            trailingIcon: AppIcons.chevronRight,
            iconStroke: 2.2,
            onPressed: cart.isEmpty ? null : () => context.push(Routes.checkout),
          ),
        ],
      ),
    );
  }
}
