import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/features/features_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../inventory/data/stock_repository.dart';
import '../../inventory/presentation/restock_sheet.dart' show ExpiredBadge;
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../products/domain/product_modules.dart';
import '../domain/cart.dart';

/// Result of [pickModuleUnit].
sealed class ModulePickResult {
  const ModulePickResult();
}

/// Not a module product (or nothing to choose): sell it as a plain line.
class PlainProduct extends ModulePickResult {
  const PlainProduct();
}

/// The cashier chose (or the app chose, e.g. the only batch) this unit.
class Picked extends ModulePickResult {
  const Picked(this.pick);
  final ModulePick pick;
}

/// Dismissed, or nothing left to sell (every IMEI is sold / in the cart).
class PickCancelled extends ModulePickResult {
  const PickCancelled();
}

/// BUG-2: before a module product goes into the cart, find out WHICH unit:
/// - IMEI / serial (serialWarranty): always asked; only in-stock IMEIs not
///   already in the cart are offered.
/// - size × colour (variants): always asked, with each variant's stock.
/// - batch (expiryBatch): the only unexpired batch with stock is taken automatically;
///   otherwise asked — earliest expiry first (FEFO), expired ones last in red,
///   and selling from an expired batch needs an explicit confirm.
/// Products without IMEIs / variants / batches are sold as before.
Future<ModulePickResult> pickModuleUnit(BuildContext context, WidgetRef ref, Product p, Cart cart) async {
  final f = ref.read(tenantFeaturesProvider);
  final products = ref.read(productRepositoryProvider);

  if (f.serialWarranty) {
    final serials = await products.watchSerials(p.id).first;
    if (serials.isNotEmpty) {
      final inCart = cart.serialIds;
      final free = serials.where((s) => s.status == SerialStatus.inStock && !inCart.contains(s.id)).toList();
      if (!context.mounted) return const PickCancelled();
      return _sheet(
        context,
        title: 'ဘယ် IMEI လဲ?',
        subtitle: p.name,
        empty: 'ရောင်းစရာ IMEI မကျန်တော့ပါ',
        options: [
          for (final s in free)
            (pick: (serialId: s.id, variantId: null, batchId: null, label: 'IMEI ${s.serial}'), title: s.serial, trailing: '', expired: false),
        ],
      );
    }
  }

  if (f.variants) {
    final variants = await products.watchVariants(p.id).first;
    if (variants.isNotEmpty) {
      final moves = await ref.read(stockRepositoryProvider).watchAll().first;
      int stockOf(ProductVariant v) =>
          moves.where((m) => m.variantId == v.id && m.deletedAt == null).fold(0, (a, m) => a + m.qtyMilli);
      if (!context.mounted) return const PickCancelled();
      return _sheet(
        context,
        title: 'ဘယ် Size / အရောင် လဲ?',
        subtitle: p.name,
        empty: '',
        options: [
          for (final v in variants)
            (
              pick: (variantId: v.id, batchId: null, serialId: null, label: v.label),
              title: v.label,
              trailing: 'ကျန် ${Qty.format(stockOf(v))}',
              expired: false,
            ),
        ],
      );
    }
  }

  // Batches only for products that track expiry; others sell as plain products,
  // even with old batches: no batch sheet, no expired confirm (BUG-20).
  if (f.expiryBatch && p.expiryAlertDays != null) {
    final batches = [...await products.watchBatches(p.id).first]..sort(_fefo);
    if (batches.isNotEmpty) {
      ModulePick pickOf(ProductBatch b) => (batchId: b.id, variantId: null, serialId: null, label: 'Batch ${b.batchNo}');
      final now = DateTime.now();
      final withStock = batches.where((b) => b.qtyMilli > 0).toList();
      // Expired batches are never picked automatically, and listed after the good ones.
      final good = withStock.where((b) => !b.isExpired(now)).toList();
      final expired = withStock.where((b) => b.isExpired(now)).toList();
      if (good.length == 1) return Picked(pickOf(good.single));
      if (!context.mounted) return const PickCancelled();
      final dates = DateFormat('yyyy-MM-dd');
      final shown = withStock.isEmpty ? batches : [...good, ...expired];
      final result = await _sheet(
        context,
        title: 'ဘယ် Batch လဲ?',
        subtitle: '${p.name} · သက်တမ်းစောတာ အပေါ်ဆုံး',
        empty: '',
        options: [
          for (final b in shown)
            (
              pick: pickOf(b),
              title: b.expiryDate == null ? b.batchNo : '${b.batchNo} · ${dates.format(b.expiryDate!)}',
              trailing: 'ကျန် ${Qty.format(b.qtyMilli)}',
              expired: b.isExpired(now),
            ),
        ],
      );
      // Selling from an expired batch needs an explicit confirm.
      if (result case Picked(:final pick)) {
        final b = batches.firstWhere((x) => x.id == pick.batchId);
        if (b.isExpired(now)) {
          if (!context.mounted) return const PickCancelled();
          final ok = await confirmSellExpired(context, b);
          if (!ok) return const PickCancelled();
        }
      }
      return result;
    }
  }

  return const PlainProduct();
}

/// Earliest expiry first; batches without a date last; then oldest received.
int _fefo(ProductBatch a, ProductBatch b) {
  final ea = a.expiryDate, eb = b.expiryDate;
  if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
  if ((ea == null) != (eb == null)) return ea == null ? 1 : -1;
  return a.createdAt.compareTo(b.createdAt);
}

typedef _Option = ({ModulePick pick, String title, String trailing, bool expired});

/// "This batch has expired — sell it anyway?" Only an explicit yes sells it.
Future<bool> confirmSellExpired(BuildContext context, ProductBatch b) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Batch ${b.batchNo} သက်တမ်းကုန်နေပါပြီ', style: AppText.s(16, weight: AppText.w700, color: AppColors.danger)),
        content: Text(
          'သက်တမ်းကုန်ရက် ${DateFormat('yyyy-MM-dd').format(b.expiryDate!)}။ ဒီ Batch ကနေ ရောင်းမှာ သေချာလား?',
          style: AppText.s(14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မရောင်းတော့ပါ')),
          TextButton(
            key: const ValueKey('sellExpired'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('သိပြီး ရောင်းမယ်', style: AppText.s(14, weight: AppText.w700, color: AppColors.danger)),
          ),
        ],
      ),
    ) ??
    false;

Future<ModulePickResult> _sheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String empty,
  required List<_Option> options,
}) async {
  final picked = await showModalBottomSheet<ModulePick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(padding: EdgeInsets.zero),
              const SizedBox(height: 12),
              Semantics(header: true, child: Text(title, style: AppText.s(18, weight: AppText.w700))),
              Text(subtitle, style: AppText.s(13, color: AppColors.muted)),
              const SizedBox(height: 12),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(empty, textAlign: TextAlign.center, style: AppText.s(14, color: AppColors.danger)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      final o = options[i];
                      return InkWell(
                        onTap: () => Navigator.pop(ctx, o.pick),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(o.title,
                                      style: AppText.s(15,
                                          weight: AppText.w600, color: o.expired ? AppColors.danger : AppColors.text)),
                                ),
                                if (o.expired) ...[const ExpiredBadge(), const SizedBox(width: 8)],
                                if (o.trailing.isNotEmpty)
                                  Text(o.trailing, style: AppText.s(13, color: AppColors.muted)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return picked == null ? const PickCancelled() : Picked(picked);
}
