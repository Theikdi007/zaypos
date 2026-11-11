import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/features/features_providers.dart';
import 'package:zaypos_app/core/features/shop_template.dart';
import 'package:zaypos_app/core/features/tenant_features.dart';

import 'helpers.dart';

Set<FeatureFlag> _on(TenantFeatures f) => FeatureFlag.values.where((x) => x.read(f)).toSet();

void main() {
  test('template -> TenantFeatures mapping', () {
    final expected = <String, Set<FeatureFlag>>{
      'grocery': {FeatureFlag.quickSale, FeatureFlag.stock, FeatureFlag.presetCatalog},
      'pharmacy': {FeatureFlag.quickSale, FeatureFlag.stock, FeatureFlag.presetCatalog, FeatureFlag.expiryBatch},
      'phone': {FeatureFlag.quickSale, FeatureFlag.stock, FeatureFlag.presetCatalog, FeatureFlag.serialWarranty},
      'fashion': {FeatureFlag.quickSale, FeatureFlag.stock, FeatureFlag.variants},
      'hardware': {
        FeatureFlag.quickSale,
        FeatureFlag.stock,
        FeatureFlag.presetCatalog,
        FeatureFlag.decimalQty,
        FeatureFlag.quotation,
      },
      'service': {FeatureFlag.quickSale, FeatureFlag.serviceItems},
      'restaurant': <FeatureFlag>{},
      'other': <FeatureFlag>{},
    };
    expect(ShopTemplate.all.map((t) => t.id).toSet(), expected.keys.toSet());
    for (final t in ShopTemplate.all) {
      expect(_on(t.features), expected[t.id], reason: t.id);
    }
  });

  test('only restaurant is marked v2', () {
    expect(ShopTemplate.all.where((t) => t.soon).map((t) => t.id), ['restaurant']);
  });

  test('selecting a template reseeds the tenant flags; toggles then override', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(_on(c.read(tenantFeaturesProvider)), _on(ShopTemplate.byId('grocery').features));

    c.read(shopTemplateProvider.notifier).select('hardware');
    expect(c.read(tenantFeaturesProvider).decimalQty, isTrue);

    c.read(tenantFeaturesProvider.notifier).set(FeatureFlag.decimalQty, false);
    expect(c.read(tenantFeaturesProvider).decimalQty, isFalse);
    expect(c.read(tenantFeaturesProvider).quotation, isTrue);
  });

  test('FeatureFlag read/write round-trips every flag', () {
    for (final f in FeatureFlag.values) {
      final on = f.write(const TenantFeatures(), true);
      expect(_on(on), {f});
      expect(_on(f.write(on, false)), isEmpty);
    }
  });
}
