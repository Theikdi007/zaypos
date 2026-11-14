import 'package:flutter/painting.dart';

import '../theme/app_colors.dart';
import 'tenant_features.dart';

/// A shop type is only a TEMPLATE: it seeds [TenantFeatures] and supplies
/// template data (labels, sample categories/units). UI never branches on [id].
class ShopTemplate {
  const ShopTemplate({
    required this.id,
    required this.label,
    required this.initial,
    required this.tint,
    required this.desc,
    required this.features,
    this.presetCount = 0,
    this.soon = false,
    this.productBadge,
    this.namePlaceholder = '',
    this.sampleCost = 0,
    this.samplePrice = 0,
    this.categories = const [],
    this.units = const [],
  });

  final String id;
  final String label;
  final String initial;
  final Color tint;
  final String desc;
  final TenantFeatures features;
  final int presetCount;
  final bool soon;

  // Add-product template data
  final String? productBadge;
  final String namePlaceholder;
  final int sampleCost;
  final int samplePrice;
  final List<String> categories;
  final List<String> units;

  static ShopTemplate byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  static const all = <ShopTemplate>[
    ShopTemplate(
      id: 'grocery',
      label: 'ကုန်စုံဆိုင်',
      initial: 'က',
      tint: AppColors.tintGreen,
      desc: 'ပစ္စည်း ၂၀ ကြိုထည့်ပြီး · ပြည်/ပိဿာ',
      presetCount: 20,
      features: TenantFeatures(quickSale: true, stock: true, presetCatalog: true),
      productBadge: 'ကုန်စုံ',
      namePlaceholder: 'ဥပမာ - ရေသန့် 1L',
      sampleCost: 450,
      samplePrice: 600,
      categories: ['စားသောက်ကုန်', 'အချိုရည်', 'အိမ်သုံး', 'မုန့်'],
      units: ['ခု', 'ဗူး', 'ပြည်', 'ပိဿာ', 'ထုပ်'],
    ),
    ShopTemplate(
      id: 'pharmacy',
      label: 'ဆေးဆိုင်',
      initial: 'ဆ',
      tint: AppColors.tintBlue,
      desc: 'သက်တမ်းကုန်ရက် · Batch · ကုန်ခါနီး သတိပေး',
      presetCount: 0,
      features: TenantFeatures(
          quickSale: true, stock: true, presetCatalog: true, expiryBatch: true),
      productBadge: 'ဆေးဆိုင်',
      namePlaceholder: 'ဥပမာ - Paracetamol 500mg',
      sampleCost: 1200,
      samplePrice: 1500,
      categories: ['အကိုက်အခဲပျောက်', 'ဗီတာမင်', 'ပဋိဇီဝ', 'အခြား'],
      units: ['ကဒ်', 'ဘူး', 'ပုလင်း', 'လုံး'],
    ),
    ShopTemplate(
      id: 'phone',
      label: 'ဖုန်း / Electronics',
      initial: 'ဖ',
      tint: AppColors.tintIndigo,
      desc: 'IMEI / Serial · အာမခံရက်',
      presetCount: 0,
      features: TenantFeatures(
          quickSale: true,
          stock: true,
          presetCatalog: true,
          serialWarranty: true),
      productBadge: 'ဖုန်းဆိုင်',
      namePlaceholder: 'ဥပမာ - Type-C အားသွင်းကြိုး',
      sampleCost: 3500,
      samplePrice: 6000,
      categories: ['ဖုန်း', 'အားသွင်းကြိုး', 'နားကြပ်', 'Case'],
      units: ['ခု', 'လုံး', 'ဘူး'],
    ),
    ShopTemplate(
      id: 'fashion',
      label: 'အဝတ် / အလှကုန်',
      initial: 'အ',
      tint: AppColors.tintPink,
      desc: 'Size · အရောင် ခွဲမှတ်',
      features: TenantFeatures(quickSale: true, stock: true, variants: true),
      productBadge: 'အဝတ်အထည်',
      namePlaceholder: 'ဥပမာ - ချည်သား တီရှပ်',
      sampleCost: 8000,
      samplePrice: 12000,
      categories: ['အမျိုးသား', 'အမျိုးသမီး', 'ကလေး', 'အလှကုန်'],
      units: ['ထည်', 'စုံ', 'ခု'],
    ),
    ShopTemplate(
      id: 'hardware',
      label: 'Hardware / ဆောက်လုပ်ရေး',
      initial: 'H',
      tint: AppColors.tintAmber,
      desc: 'ပေ/ကီလို/အိတ် · ဒသမ · Quotation',
      presetCount: 0,
      features: TenantFeatures(
          quickSale: true,
          stock: true,
          presetCatalog: true,
          decimalQty: true,
          quotation: true),
      productBadge: 'Hardware',
      namePlaceholder: 'ဥပမာ - ဘိလပ်မြေ (၁ အိတ်)',
      sampleCost: 9800,
      samplePrice: 10500,
      categories: ['ဆောက်လုပ်ရေး', 'ပိုက်', 'လျှပ်စစ်', 'ဆေးသုတ်'],
      units: ['အိတ်', 'ပေ', 'ကီလို', 'ချောင်း', 'ခု'],
    ),
    ShopTemplate(
      id: 'service',
      label: 'ဝန်ဆောင်မှု',
      initial: 'ဝ',
      tint: AppColors.tintOrange,
      desc: 'Stock မလိုတဲ့ service · ချိန်းဆို',
      features: TenantFeatures(quickSale: true, serviceItems: true),
    ),
    ShopTemplate(
      id: 'restaurant',
      label: 'စားသောက် / ကော်ဖီ',
      initial: 'စ',
      tint: AppColors.tintRed,
      desc: 'စားပွဲ · Order',
      soon: true,
      features: TenantFeatures(),
    ),
    ShopTemplate(
      id: 'other',
      label: 'အခြား',
      initial: '+',
      tint: AppColors.tintGray,
      desc: 'Core feature တွေပဲ · ကိုယ်တိုင်ဖွင့်',
      features: TenantFeatures(),
    ),
  ];
}
