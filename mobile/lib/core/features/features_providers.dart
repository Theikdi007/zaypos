import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shop_template.dart';
import 'tenant_features.dart';

/// Current shop template (set at registration; changeable from Settings).
class ShopTemplateNotifier extends Notifier<ShopTemplate> {
  @override
  ShopTemplate build() => ShopTemplate.byId('grocery');

  void select(String id) => state = ShopTemplate.byId(id);
}

final shopTemplateProvider =
    NotifierProvider<ShopTemplateNotifier, ShopTemplate>(
        ShopTemplateNotifier.new);

/// Active feature flags. Seeded from the template, then toggled per tenant.
class TenantFeaturesNotifier extends Notifier<TenantFeatures> {
  @override
  TenantFeatures build() => ref.watch(shopTemplateProvider).features;

  void set(FeatureFlag flag, bool value) => state = flag.write(state, value);
}

final tenantFeaturesProvider =
    NotifierProvider<TenantFeaturesNotifier, TenantFeatures>(
        TenantFeaturesNotifier.new);
