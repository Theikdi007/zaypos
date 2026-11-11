import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/features/shop_template.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_switch_tile.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../../auth/data/session.dart';
import '../../inventory/domain/stock_movement.dart';
import '../application/product_service.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import 'sections/feature_sections.dart';

/// One Add Product screen; sections appear according to [TenantFeatures].
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  late final ShopTemplate _t = ref.read(shopTemplateProvider);
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  late final _cost = TextEditingController(text: '${_t.sampleCost}');
  late final _price = TextEditingController(text: '${_t.samplePrice}');
  final _wholesale = TextEditingController();
  final _stock = TextEditingController();
  final _alert = TextEditingController();
  final _batchNo = TextEditingController();
  DateTime? _expiry;
  int _expiryWarnDays = 30;
  int _warrantyMonths = 6;
  late String? _category = _t.categories.isEmpty ? null : _t.categories.first;
  late String? _unit = _t.units.isEmpty ? null : _t.units.first;

  bool _track = true;
  bool _serial = true;
  final _imeis = <String>[];
  final _sizes = {'S': false, 'M': true, 'L': true, 'XL': false, 'XXL': false};
  final _colors = {'အနက်': true, 'အဖြူ': true, 'အပြာ': false, 'အနီ': false};
  /// Variant label -> stock (milli-units).
  final _variantStock = <String, int>{};
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _cost.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
    _name.addListener(() {
      if (_showErrors) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _barcode, _cost, _price, _wholesale, _stock, _alert, _batchNo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final features = ref.read(tenantFeaturesProvider);
    final name = _name.text.trim();
    final price = int.tryParse(_price.text) ?? 0;
    if (name.isEmpty || price <= 0) {
      setState(() => _showErrors = true);
      return;
    }
    final tenantId = ref.read(tenantIdProvider);
    final t = nowUtc();
    final productId = newId();
    final variants = <ProductVariant>[];
    final batches = <ProductBatch>[];
    final serials = <ProductSerial>[];
    final movements = <StockMovement>[];
    StockMovement restock(int qty, {String? variantId, String? batchId}) => restockMovement(
          tenantId: tenantId,
          productId: productId,
          qtyMilli: qty,
          variantId: variantId,
          batchId: batchId,
          note: 'initial',
        );
    if (features.stock && _track) {
      if (features.variants) {
        for (final e in _sizes.entries.where((e) => e.value)) {
          for (final c in _colors.entries.where((c) => c.value)) {
            final s = _variantStock['${e.key} · ${c.key}'] ?? 0;
            final variantId = newId();
            if (s != 0) movements.add(restock(s, variantId: variantId));
            variants.add(ProductVariant(
              id: variantId,
              tenantId: tenantId,
              productId: productId,
              size: e.key,
              color: c.key,
              createdAt: t,
              updatedAt: t,
            ));
          }
        }
      } else if (features.serialWarranty && _serial) {
        if (_imeis.isNotEmpty) movements.add(restock(Qty.units(_imeis.length)));
      } else {
        final q = Qty.parse(_stock.text, decimal: features.decimalQty) ?? 0;
        // Expiry-tracked shops receive stock into a batch.
        final hasBatch = features.expiryBatch && (_batchNo.text.trim().isNotEmpty || _expiry != null);
        final batchId = hasBatch ? newId() : null;
        if (hasBatch) {
          batches.add(ProductBatch(
            id: batchId!,
            tenantId: tenantId,
            productId: productId,
            batchNo: _batchNo.text.trim(),
            expiryDate: _expiry == null ? null : DateTime.utc(_expiry!.year, _expiry!.month, _expiry!.day),
            qtyMilli: q,
            createdAt: t,
            updatedAt: t,
          ));
        }
        if (q != 0) movements.add(restock(q, batchId: batchId));
      }
    }
    if (features.serialWarranty && _serial) {
      for (final imei in _imeis) {
        serials.add(ProductSerial(
          id: newId(),
          tenantId: tenantId,
          productId: productId,
          serial: imei,
          status: SerialStatus.inStock,
          createdAt: t,
          updatedAt: t,
        ));
      }
    }
    // Product + module rows + initial stock: one unit of work.
    await ref.read(productServiceProvider).create(
          Product(
            id: productId,
            tenantId: tenantId,
            name: name,
            cost: int.tryParse(_cost.text) ?? 0,
            price: price,
            wholesalePrice: features.quotation ? int.tryParse(_wholesale.text) : null,
            lowAlertMilli: Qty.parse(_alert.text, decimal: features.decimalQty) ?? Qty.units(5),
            category: _category ?? '',
            unit: _unit ?? '',
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            tint: _t.tint.toARGB32(),
            initial: String.fromCharCode(name.runes.first),
            warrantyMonths: features.serialWarranty && _warrantyMonths > 0 ? _warrantyMonths : null,
            expiryAlertDays: features.expiryBatch ? _expiryWarnDays : null,
            createdAt: t,
            updatedAt: t,
          ),
          variants: variants,
          batches: batches,
          serials: serials,
          initialStock: movements,
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(tenantFeaturesProvider);
    final cost = int.tryParse(_cost.text) ?? 0;
    final price = int.tryParse(_price.text) ?? 0;
    final margin = price - cost;
    // Integer percent, rounded half away from zero.
    final pct = cost > 0 ? (margin * 200 + (margin >= 0 ? cost : -cost)) ~/ (2 * cost) : 0;
    final ok = margin >= 0;
    final serialMode = f.serialWarranty && _serial;
    final showStockInputs = _track && !serialMode && !f.variants;
    final stockHint = f.variants
        ? 'Variant တစ်ခုချင်း stock ကို အပေါ်မှာ ထည့်ပါ'
        : serialMode
            ? 'IMEI အရေအတွက်နဲ့ အလိုအလျောက် တွက်မယ်'
            : 'ရောင်းတိုင်း အလိုအလျောက် နုတ်ပေးမယ်';
    // Decimal input only when TenantFeatures.decimalQty is on (Qty: max 3 dp).
    final qtyFormatter = FilteringTextInputFormatter.allow(RegExp(f.decimalQty ? r'^\d*\.?\d{0,3}' : r'^\d*'));
    final numKb = TextInputType.numberWithOptions(decimal: f.decimalQty);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'ပစ္စည်းအသစ်',
            leadingIcon: AppIcons.close,
            leadingLabel: 'ပိတ်ရန်',
            onBack: () => context.pop(),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: _t.tint, borderRadius: AppRadius.chipR),
              child: Text('${_t.productBadge ?? _t.label} template',
                  style: AppText.s(12, weight: AppText.w700, color: AppColors.textStrong)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: _gap14([
                if (f.presetCatalog && _t.presetCount > 0)
                  PrimaryButton(
                    label: 'ကြိုတင်စာရင်း (${_t.presetCount}) ထဲက ရှာမယ်',
                    variant: ButtonVariant.soft,
                    icon: AppIcons.search,
                    height: 52,
                    radius: 14,
                    fontSize: 14,
                    onPressed: () {},
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      label: 'ဓာတ်ပုံ ထည့်ရန်',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(16),
                        child: const DashedBox(
                          radius: 16,
                          background: AppColors.surface,
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: Center(
                              child: AppIcon(AppIcons.camera,
                                  size: 28, strokeWidth: 1.8, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LabeledField(
                        label: 'ပစ္စည်းအမည်',
                        required: true,
                        child: AppInput(
                          key: const ValueKey('productName'),
                          controller: _name,
                          hint: _t.namePlaceholder,
                          semanticLabel: 'ပစ္စည်းအမည်',
                          borderColor: _showErrors && _name.text.trim().isEmpty ? AppColors.danger : AppColors.inputBorder,
                        ),
                      ),
                    ),
                  ],
                ),
                FormSection(
                  gap: 14,
                  children: [
                    LabeledField(
                      label: 'Barcode',
                      child: Row(
                        children: [
                          Expanded(
                            child: AppInput(
                              controller: _barcode,
                              hint: 'Scan ဖတ် သို့မဟုတ် ရိုက်ထည့်',
                              semanticLabel: 'Barcode',
                            ),
                          ),
                          const SizedBox(width: 8),
                          const ScanSquare(label: 'Barcode scan'),
                        ],
                      ),
                    ),
                    TwoCol(
                      LabeledField(
                        label: 'အမျိုးအစား',
                        child: _category == null
                            ? const AppInput()
                            : AppSelect<String>(
                                label: 'အမျိုးအစား',
                                items: [for (final c in _t.categories) (c, c)],
                                value: _category!,
                                onChanged: (v) => setState(() => _category = v),
                              ),
                      ),
                      LabeledField(
                        label: 'ယူနစ်',
                        child: _unit == null
                            ? const AppInput()
                            : AppSelect<String>(
                                label: 'ယူနစ်',
                                items: [for (final u in _t.units) (u, u)],
                                value: _unit!,
                                onChanged: (v) => setState(() => _unit = v),
                              ),
                      ),
                    ),
                  ],
                ),
                FormSection(
                  title: 'ဈေးနှုန်း',
                  children: [
                    TwoCol(
                      LabeledField(label: 'ဝယ်ဈေး (Ks)', small: true, child: _moneyInput(_cost, 'ဝယ်ဈေး')),
                      LabeledField(
                        label: 'ရောင်းဈေး (Ks)',
                        small: true,
                        required: true,
                        child: _moneyInput(_price, 'ရောင်းဈေး', error: _showErrors && price <= 0),
                      ),
                    ),
                    if (f.quotation)
                      LabeledField(
                        label: 'လက်ကား / ကန်ထရိုက်တာ ဈေး (Ks)',
                        small: true,
                        child: _moneyInput(_wholesale, 'လက်ကား ဈေး'),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: ok ? AppColors.successBg : AppColors.dangerBg,
                        borderRadius: AppRadius.inputR,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('တစ်ခုချင်း အမြတ်',
                              style: AppText.s(14, weight: AppText.w600, color: ok ? AppColors.success : AppColors.danger)),
                          Text('${ok ? '+' : '-'}${formatKs(margin.abs())} ($pct%)',
                              style: AppText.s(14, weight: AppText.w600, color: ok ? AppColors.success : AppColors.danger)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (f.expiryBatch)
                  ExpiryBatchSection(
                    batchNo: _batchNo,
                    expiry: _expiry,
                    onExpiry: (d) => setState(() => _expiry = d),
                    warnDays: _expiryWarnDays,
                    onWarnDays: (d) => setState(() => _expiryWarnDays = d),
                  ),
                if (f.serialWarranty)
                  SerialWarrantySection(
                    serial: _serial,
                    onSerialChanged: (v) => setState(() => _serial = v),
                    imeis: _imeis,
                    onAddImei: (v) => setState(() => _imeis.add(v)),
                    warrantyMonths: _warrantyMonths,
                    onWarrantyChanged: (m) => setState(() => _warrantyMonths = m),
                  ),
                if (f.variants)
                  VariantsSection(
                    sizes: _sizes,
                    colors: _colors,
                    onToggleSize: (k) => setState(() => _sizes[k] = !_sizes[k]!),
                    onToggleColor: (k) => setState(() => _colors[k] = !_colors[k]!),
                    stock: _variantStock,
                    onStockChanged: (v, milli) => _variantStock[v] = milli,
                  ),
                if (f.stock)
                  FormSection(
                    children: [
                      AppSwitchTile(
                        title: 'Stock မှတ်မယ်',
                        description: stockHint,
                        titleSize: 15,
                        padding: EdgeInsets.zero,
                        value: _track,
                        onChanged: (v) => setState(() => _track = v),
                      ),
                      if (showStockInputs)
                        TwoCol(
                          LabeledField(
                            label: 'လက်ရှိ အရေအတွက်',
                            small: true,
                            child: AppInput(
                              key: const ValueKey('stockQty'),
                              controller: _stock,
                              fontSize: 16,
                              hint: f.decimalQty ? '0.00' : '0',
                              keyboardType: numKb,
                              inputFormatters: [qtyFormatter],
                              semanticLabel: 'လက်ရှိ အရေအတွက်',
                            ),
                          ),
                          LabeledField(
                            label: 'နည်းရင် သတိပေး',
                            small: true,
                            child: AppInput(
                              controller: _alert,
                              fontSize: 16,
                              hint: '5',
                              keyboardType: numKb,
                              inputFormatters: [qtyFormatter],
                              semanticLabel: 'နည်းရင် သတိပေး',
                            ),
                          ),
                        ),
                      if (f.decimalQty)
                        Text('ဒသမ အရေအတွက် ဖွင့်ထားသည် (ဥပမာ 2.5 ပေ၊ 0.75 ကီလို)',
                            style: AppText.s(12, weight: AppText.w600, color: AppColors.success)),
                    ],
                  ),
              ]),
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

  Widget _moneyInput(TextEditingController c, String label, {bool error = false}) => AppInput(
        controller: c,
        fontSize: 16,
        fontWeight: AppText.w600,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        semanticLabel: label,
        borderColor: error ? AppColors.danger : AppColors.inputBorder,
      );

  List<Widget> _gap14(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 14), items[i]],
      ];
}
