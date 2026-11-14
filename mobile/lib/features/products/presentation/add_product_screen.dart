import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/features/shop_template.dart';
import '../../../core/sync/sync_limits.dart';
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
import '../../../core/features/tenant_features.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../application/product_service.dart';
import '../data/product_providers.dart';
import '../domain/product.dart';
import '../domain/product_modules.dart';
import '../../scan/barcode_scanner.dart';
import 'sections/edit_module_sections.dart';
import 'sections/feature_sections.dart';

/// One Add Product screen; sections appear according to [TenantFeatures].
/// With [editing] the same form edits a saved product (Products → tap a row):
/// its own fields only — stock, IMEIs, variants and batches are received
/// through "Stock ဖြည့်မယ်", not edited here.
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.editing, this.initialBarcode});

  /// New product from POS: an unknown barcode that was scanned.
  final String? initialBarcode;

  /// The product being edited; null = a new product.
  final Product? editing;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

/// Edit route: looks the product up, then shows [AddProductScreen] in edit mode.
class EditProductScreen extends ConsumerWidget {
  const EditProductScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productByIdProvider(productId));
    return product.when(
      data: (p) => p == null
          ? Scaffold(body: Center(child: Text('ပစ္စည်း မတွေ့ပါ', style: AppText.s(15, color: AppColors.muted))))
          : AddProductScreen(key: ValueKey(p.id), editing: p),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
    );
  }
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  late final ShopTemplate _t = ref.read(shopTemplateProvider);
  late final Product? _p = widget.editing;
  bool get _isEdit => _p != null;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _barcode = TextEditingController(text: _p?.barcode ?? widget.initialBarcode ?? '');

  /// Camera scan into the barcode field.
  Future<void> _scanBarcode() async {
    final code = await ref.read(barcodeScannerProvider).scan(context, title: 'Barcode scan');
    if (code == null || !mounted) return;
    _barcode.text = ref.read(syncLimitsProvider).normalize('products.barcode', code);
  }
  late final _cost = TextEditingController(text: '${_p?.cost ?? _t.sampleCost}');
  late final _price = TextEditingController(text: _p == null ? '${_t.samplePrice}' : (_p.price > 0 ? '${_p.price}' : ''));
  late final _wholesale = TextEditingController(text: _p?.wholesalePrice?.toString() ?? '');
  final _stock = TextEditingController();
  /// Low-stock alert 0 = "no alert" (the field is left empty).
  static const noLowAlert = 0;
  late final _alert = TextEditingController(
      text: _p == null || _p.lowAlertMilli == noLowAlert ? '' : Qty.format(_p.lowAlertMilli));

  /// Edit form, expiry tracked: stock outside any batch that must go into an
  /// opening batch on save (BUG-22). 0 when not applicable.
  int _unbatchedNow(TenantFeatures f) {
    if (!_isEdit || !f.expiryBatch || !f.stock || _expiryWarnDays == ExpiryBatchSection.noExpiry) return 0;
    final n = ref.read(unbatchedStockProvider(_p!.id)).value ?? 0;
    return n > 0 ? n : 0;
  }

  /// Add Product: adds an IMEI typed but not yet "+"-ed (BUG-19).
  bool Function()? _commitTypedImei;

  /// IMEIs / batches / sizes-colours added in the edit form (BUG-12).
  final _pending = PendingModules();
  final _batchNo = TextEditingController();
  DateTime? _expiry;
  // Expiry tracking is opt-in: a new product starts at "သက်တမ်း မမှတ်ပါ" (owner decision). Edit: as saved.
  late int _expiryWarnDays = _p == null ? ExpiryBatchSection.noExpiry : (_p.expiryAlertDays ?? ExpiryBatchSection.noExpiry);
  late int _warrantyMonths = _p == null ? 6 : (_p.warrantyMonths ?? 0);
  late String? _category = _p?.category ?? (_t.categories.isEmpty ? null : _t.categories.first);
  late String? _unit = _p != null ? (_p.unit.isEmpty && _t.units.isEmpty ? null : _p.unit) : (_t.units.isEmpty ? null : _t.units.first);

  /// Template options plus the saved value when the template lacks it (e.g. a preset's category).
  List<(String, String)> _options(List<String> template, String? current) =>
      [for (final v in {...template, ?current}) (v, v)];

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

  /// Field → message, from the server's rules (/sync/limits).
  Map<String, String> _errors = {};

  /// Category when the template offers none: the server requires one.
  static const defaultCategory = 'အထွေထွေ';

  /// IMEI / serial: normalized like the server, checked, de-duplicated.
  String? _addImei(String raw) {
    final limits = ref.read(syncLimitsProvider);
    final v = limits.normalize('productSerials.serial', raw);
    final error = limits.checkText('productSerials.serial', v, label: 'IMEI / Serial');
    if (error != null) return error;
    if (_imeis.contains(v)) return 'ဒီ IMEI ထည့်ပြီးသားပါ။';
    // Already on this phone (any product): refused (BUG-18).
    if ((ref.read(knownSerialsProvider).value ?? const <String>{}).contains(v)) return 'ဒီ IMEI ရှိပြီးသားပါ။';
    setState(() => _imeis.add(v));
    return null;
  }

  Future<void> _save() async {
    final features = ref.read(tenantFeaturesProvider);
    final limits = ref.read(syncLimitsProvider);
    final name = _name.text.trim();
    final price = int.tryParse(_price.text) ?? 0;
    final barcode = limits.normalize('products.barcode', _barcode.text);
    // A typed IMEI not "+"-ed is added now, or blocks the save with its message (BUG-19).
    if (!_isEdit && features.serialWarranty && !(_commitTypedImei?.call() ?? true)) {
      setState(() => _showErrors = true);
      return;
    }
    final tracksExpiry = features.expiryBatch && _expiryWarnDays != ExpiryBatchSection.noExpiry;
    final hasBatchInput = tracksExpiry && (_batchNo.text.trim().isNotEmpty || _expiry != null);
    // Opening stock of an expiry-tracked product must go into a batch (BUG-21).
    final openingQty = Qty.parse(_stock.text, decimal: features.decimalQty) ?? 0;
    final needsBatch = !_isEdit &&
        tracksExpiry &&
        features.stock &&
        _track &&
        !features.variants &&
        !(features.serialWarranty && _serial) &&
        openingQty > 0 &&
        (_batchNo.text.trim().isEmpty || _expiry == null);
    // BUG-22: editing a product that tracks expiry (e.g. just switched on) while
    // it has stock outside any batch: that stock goes into an opening batch.
    final unbatched = _unbatchedNow(features);
    final needsOpeningBatch = unbatched > 0;
    final existingBatches = _isEdit ? ref.read(productBatchesProvider(_p!.id)).value ?? const <ProductBatch>[] : const <ProductBatch>[];
    final errors = <String, String>{
      for (final (key, error) in [
        ('name', limits.checkText('products.name', name, label: 'ပစ္စည်းအမည်')),
        ('barcode', limits.checkText('products.barcode', barcode.isEmpty ? null : barcode, label: 'Barcode')),
        ('category', limits.checkText('products.category', _category ?? defaultCategory, label: 'အမျိုးအစား')),
        ('unit', limits.checkText('products.unit', _unit ?? '', label: 'ယူနစ်')),
        ('cost', limits.checkNumber('products.cost', int.tryParse(_cost.text), label: 'ဝယ်ဈေး')),
        if (hasBatchInput) ('batchNo', limits.checkText('productBatches.batchNo', _batchNo.text, label: 'Batch နံပါတ်')),
      ])
        key: ?error,
    };
    if (name.isEmpty) errors['name'] ??= 'ပစ္စည်းအမည် ထည့်ပါ။';
    if (price <= 0) errors['price'] = 'ရောင်းဈေး ထည့်ပါ။';
    if (needsBatch) {
      // Owner decision: batch number AND expiry date for tracked opening stock.
      errors['batchNo'] = _batchNo.text.trim().isEmpty
          ? "သက်တမ်းမှတ်တဲ့ ပစ္စည်းမို့ Batch နံပါတ် ထည့်ပါ (သို့ 'သက်တမ်း မမှတ်ပါ' ရွေးပါ)။"
          : 'သက်တမ်းမှတ်တဲ့ ပစ္စည်းမို့ သက်တမ်းကုန်ရက် ရွေးပါ။';
    }
    if (needsOpeningBatch && !errors.containsKey('batchNo')) {
      final no = _batchNo.text.trim();
      if (no.isEmpty || _expiry == null) {
        errors['batchNo'] = 'လက်ရှိ Batch မရှိတဲ့ stock ${Qty.format(unbatched)} ခု အတွက် Batch နံပါတ် နဲ့ သက်တမ်းကုန်ရက် ထည့်ပါ။';
      } else if (existingBatches.any((b) => b.batchNo == no)) {
        errors['batchNo'] = 'ဒီ Batch ရှိပြီးသားပါ။';
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _showErrors = true;
        _errors = errors;
      });
      return;
    }
    final editing = _p;
    if (editing != null) {
      // A typed IMEI / batch / size not yet "+ ထည့်"-ed is added now, or blocks
      // the save with its message — never dropped (BUG-17).
      if (!(_pending.commitTyped?.call() ?? true)) {
        setState(() => _showErrors = true);
        return;
      }
      final t = nowUtc();
      final tenantId = editing.tenantId;
      final pending = _pending;
      // BUG-22: move the stock outside batches into the opening batch (same unit),
      // so batch stock = product stock. Per size/colour, so variant stock is unchanged.
      ProductBatch? opening;
      final openingMoves = <StockMovement>[];
      if (needsOpeningBatch) {
        opening = ProductBatch(
          id: newId(), tenantId: tenantId, productId: editing.id, batchNo: _batchNo.text.trim(),
          expiryDate: DateTime.utc(_expiry!.year, _expiry!.month, _expiry!.day), qtyMilli: unbatched,
          createdAt: t, updatedAt: t,
        );
        final byVariant = <String?, int>{};
        for (final m in await ref.read(stockRepositoryProvider).watchAll().first) {
          if (m.productId != editing.id || m.batchId != null || m.deletedAt != null) continue;
          byVariant.update(m.variantId, (v) => v + m.qtyMilli, ifAbsent: () => m.qtyMilli);
        }
        for (final MapEntry(key: v, value: sum) in byVariant.entries) {
          if (sum == 0) continue;
          for (final (qty, batchId) in [(-sum, null), (sum, opening.id)]) {
            openingMoves.add(StockMovement(
              id: newId(), tenantId: tenantId, productId: editing.id, variantId: v, batchId: batchId,
              type: StockMovementType.adjustment, qtyMilli: qty, note: 'opening batch', createdAt: t, updatedAt: t,
            ));
          }
        }
      }
      await ref.read(productServiceProvider).update(
            editing.copyWith(
            name: name,
            cost: int.tryParse(_cost.text) ?? 0,
            price: price,
            wholesalePrice: () => features.quotation ? int.tryParse(_wholesale.text) : editing.wholesalePrice,
            // A cleared field = no low-stock alert (0), not the old value.
            lowAlertMilli: features.stock
                ? (Qty.parse(_alert.text, decimal: features.decimalQty) ?? noLowAlert)
                : editing.lowAlertMilli,
            category: _category ?? defaultCategory,
            unit: _unit ?? '',
            barcode: () => barcode.isEmpty ? null : barcode,
            warrantyMonths: () => features.serialWarranty
                ? (_warrantyMonths > 0 ? _warrantyMonths : null)
                : editing.warrantyMonths,
            expiryAlertDays: () => features.expiryBatch
                ? (_expiryWarnDays == ExpiryBatchSection.noExpiry ? null : _expiryWarnDays)
                : editing.expiryAlertDays,
            initial: String.fromCharCode(name.runes.first),
          ),
            variants: [
              if (features.variants)
                for (final v in pending.variants)
                  ProductVariant(
                    id: newId(), tenantId: tenantId, productId: editing.id, size: v.size, color: v.color,
                    createdAt: t, updatedAt: t,
                  ),
            ],
            batches: [
              if (features.expiryBatch)
                for (final b in pending.batches)
                  ProductBatch(
                    id: newId(), tenantId: tenantId, productId: editing.id, batchNo: b.batchNo, expiryDate: b.expiry,
                    qtyMilli: 0, createdAt: t, updatedAt: t,
                  ),
              ?opening,
            ],
            movements: openingMoves,
            serials: [
              if (features.serialWarranty)
                for (final s in pending.imeis)
                  ProductSerial(
                    id: newId(), tenantId: tenantId, productId: editing.id, serial: s, status: SerialStatus.inStock,
                    createdAt: t, updatedAt: t,
                  ),
            ],
          );
      if (mounted) context.pop();
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
        final hasBatch = hasBatchInput;
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
            category: _category ?? defaultCategory,
            unit: _unit ?? '',
            barcode: barcode.isEmpty ? null : barcode,
            tint: _t.tint.toARGB32(),
            initial: String.fromCharCode(name.runes.first),
            warrantyMonths: features.serialWarranty && _warrantyMonths > 0 ? _warrantyMonths : null,
            expiryAlertDays: tracksExpiry ? _expiryWarnDays : null,
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
    if (_isEdit && f.expiryBatch) {
      // keep the opening-batch check (BUG-22) loaded
      ref.watch(unbatchedStockProvider(_p!.id));
      ref.watch(productBatchesProvider(_p.id));
    }
    final openingQty = _unbatchedNow(f);
    if (f.serialWarranty) ref.watch(knownSerialsProvider); // duplicate-IMEI check stays loaded
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
            title: _isEdit ? 'ပစ္စည်း ပြင်မယ်' : 'ပစ္စည်းအသစ်',
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
                // (BUG-6) No "search the preset list" button here: presets are
                // imported at registration; a picker is not built yet.
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
                        error: _errors['name'],
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
                      error: _errors['barcode'],
                      child: Row(
                        children: [
                          Expanded(
                            child: AppInput(
                              key: const ValueKey('barcode'),
                              controller: _barcode,
                              hint: 'Scan ဖတ် သို့မဟုတ် ရိုက်ထည့်',
                              semanticLabel: 'Barcode',
                            ),
                          ),
                          const SizedBox(width: 8),
                          ScanSquare(key: const ValueKey('barcodeScan'), label: 'Barcode scan', onTap: _scanBarcode),
                        ],
                      ),
                    ),
                    TwoCol(
                      LabeledField(
                        label: 'အမျိုးအစား',
                        error: _errors['category'],
                        child: _category == null
                            ? const AppInput(hint: defaultCategory)
                            : AppSelect<String>(
                                label: 'အမျိုးအစား',
                                items: _options(_t.categories, _category),
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
                                items: _options(_t.units, _unit),
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
                        error: _errors['price'],
                        child: _moneyInput(_price, 'ရောင်းဈေး',
                            error: _showErrors && price <= 0, key: const ValueKey('price')),
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
                          Flexible(
                            child: Text('တစ်ခုချင်း အမြတ်',
                                style: AppText.s(14, weight: AppText.w600, color: ok ? AppColors.success : AppColors.danger)),
                          ),
                          const SizedBox(width: 8),
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
                    batchError: _errors['batchNo'],
                    showBatch: !_isEdit || openingQty > 0,
                    note: openingQty > 0
                        ? 'လက်ရှိ Batch မရှိတဲ့ stock ${Qty.format(openingQty)} ခု ကို ဒီ Batch ထဲ ထည့်ပါမယ် · Batch နံပါတ် နဲ့ သက်တမ်းကုန်ရက် ထည့်ပါ'
                        : null,
                  ),
                if (f.serialWarranty)
                  SerialWarrantySection(
                    serial: _serial,
                    onSerialChanged: (v) => setState(() => _serial = v),
                    imeis: _imeis,
                    onAddImei: _addImei,
                    warrantyMonths: _warrantyMonths,
                    onWarrantyChanged: (m) => setState(() => _warrantyMonths = m),
                    showSerials: !_isEdit,
                    registerCommit: (f) => _commitTypedImei = f,
                    onScanImei: () => ref.read(barcodeScannerProvider).scan(context, title: 'IMEI scan'),
                  ),
                if (f.variants && !_isEdit)
                  VariantsSection(
                    sizes: _sizes,
                    colors: _colors,
                    onToggleSize: (k) => setState(() => _sizes[k] = !_sizes[k]!),
                    onToggleColor: (k) => setState(() => _colors[k] = !_colors[k]!),
                    stock: _variantStock,
                    onStockChanged: (v, milli) => _variantStock[v] = milli,
                  ),
                if (_isEdit && (f.serialWarranty || f.expiryBatch || f.variants))
                  EditModuleSections(
                    productId: _p!.id,
                    features: f,
                    pending: _pending,
                    onChanged: () => setState(() {}),
                  ),
                if (f.stock && _isEdit)
                  FormSection(
                    children: [
                      LabeledField(
                        label: 'နည်းရင် သတိပေး',
                        small: true,
                        helper: 'မထည့်ရင် သတိမပေးပါ',
                        child: AppInput(
                          key: const ValueKey('lowAlert'),
                          controller: _alert,
                          fontSize: 16,
                          hint: 'မထည့်ရင် သတိမပေး',
                          keyboardType: numKb,
                          inputFormatters: [qtyFormatter],
                          semanticLabel: 'နည်းရင် သတိပေး',
                        ),
                      ),
                      Text("Stock အရေအတွက်ကို ကုန်ပစ္စည်းစာရင်းမှ 'Stock ဖြည့်မယ်' နဲ့ ပြောင်းပါ",
                          style: AppText.s(12, color: AppColors.muted)),
                    ],
                  ),
                if (f.stock && !_isEdit)
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

  Widget _moneyInput(TextEditingController c, String label, {bool error = false, Key? key}) => AppInput(
        key: key,
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
