import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feature_repository.dart';
import 'shop_template.dart';
import 'tenant_features.dart';

/// Current shop template (set at registration; changeable from Settings).
/// Selecting a template reseeds the tenant's feature flags.
class ShopTemplateNotifier extends Notifier<ShopTemplate> {
  @override
  ShopTemplate build() => ShopTemplate.byId('grocery');

  void select(String id) {
    state = ShopTemplate.byId(id);
    ref.read(tenantFeaturesProvider.notifier).applyTemplate(state);
  }
}

final shopTemplateProvider =
    NotifierProvider<ShopTemplateNotifier, ShopTemplate>(
        ShopTemplateNotifier.new);

/// Active feature flags: the template's defaults overlaid with the flags
/// stored in the local database (tenantFeatures). Changes apply to [state]
/// at once and are saved as a setFeatures unit of work (pushed on sync).
class TenantFeaturesNotifier extends Notifier<TenantFeatures> {
  /// Saves in flight: stored values seen meanwhile may be stale.
  int _saving = 0;

  @override
  TenantFeatures build() {
    final sub = ref.read(featureRepositoryProvider).watchAll().listen((stored) {
      if (_saving == 0 && stored.isNotEmpty) state = _overlay(ref.read(shopTemplateProvider).features, stored);
    });
    ref.onDispose(sub.cancel);
    return ref.read(shopTemplateProvider).features;
  }

  static TenantFeatures _overlay(TenantFeatures base, Map<String, bool> stored) {
    var f = base;
    for (final flag in FeatureFlag.values) {
      final v = stored[flag.name];
      if (v != null) f = flag.write(f, v);
    }
    return f;
  }

  void set(FeatureFlag flag, bool value) {
    if (flag.read(state) == value) return;
    state = flag.write(state, value);
    _save({flag.name: value});
  }

  /// Every flag from [template] (registration / template change).
  void applyTemplate(ShopTemplate template) {
    state = template.features;
    _save({for (final f in FeatureFlag.values) f.name: f.read(template.features)});
  }

  void _save(Map<String, bool> values) {
    _saving++;
    unawaited(ref.read(featureServiceProvider).save(values).catchError((Object e, StackTrace s) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'features'));
    }).whenComplete(() => _saving--));
  }
}

final tenantFeaturesProvider =
    NotifierProvider<TenantFeaturesNotifier, TenantFeatures>(
        TenantFeaturesNotifier.new);
