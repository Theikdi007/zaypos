import 'package:flutter/foundation.dart';

/// Per-tenant feature flags. UI checks these flags — never the shop type.
@immutable
class TenantFeatures {
  const TenantFeatures({
    this.quickSale = false,
    this.stock = false,
    this.presetCatalog = false,
    this.expiryBatch = false,
    this.serialWarranty = false,
    this.variants = false,
    this.decimalQty = false,
    this.quotation = false,
    this.serviceItems = false,
  });

  final bool quickSale;
  final bool stock;
  final bool presetCatalog;
  final bool expiryBatch;
  final bool serialWarranty;
  final bool variants;
  final bool decimalQty;
  final bool quotation;
  final bool serviceItems;

  TenantFeatures copyWith({
    bool? quickSale,
    bool? stock,
    bool? presetCatalog,
    bool? expiryBatch,
    bool? serialWarranty,
    bool? variants,
    bool? decimalQty,
    bool? quotation,
    bool? serviceItems,
  }) {
    return TenantFeatures(
      quickSale: quickSale ?? this.quickSale,
      stock: stock ?? this.stock,
      presetCatalog: presetCatalog ?? this.presetCatalog,
      expiryBatch: expiryBatch ?? this.expiryBatch,
      serialWarranty: serialWarranty ?? this.serialWarranty,
      variants: variants ?? this.variants,
      decimalQty: decimalQty ?? this.decimalQty,
      quotation: quotation ?? this.quotation,
      serviceItems: serviceItems ?? this.serviceItems,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TenantFeatures &&
      other.quickSale == quickSale &&
      other.stock == stock &&
      other.presetCatalog == presetCatalog &&
      other.expiryBatch == expiryBatch &&
      other.serialWarranty == serialWarranty &&
      other.variants == variants &&
      other.decimalQty == decimalQty &&
      other.quotation == quotation &&
      other.serviceItems == serviceItems;

  @override
  int get hashCode => Object.hash(quickSale, stock, presetCatalog, expiryBatch,
      serialWarranty, variants, decimalQty, quotation, serviceItems);
}

/// Identifies one toggleable flag (used by the Settings screen).
enum FeatureFlag {
  quickSale,
  stock,
  presetCatalog,
  expiryBatch,
  serialWarranty,
  variants,
  decimalQty,
  quotation,
  serviceItems;

  bool read(TenantFeatures f) => switch (this) {
        quickSale => f.quickSale,
        stock => f.stock,
        presetCatalog => f.presetCatalog,
        expiryBatch => f.expiryBatch,
        serialWarranty => f.serialWarranty,
        variants => f.variants,
        decimalQty => f.decimalQty,
        quotation => f.quotation,
        serviceItems => f.serviceItems,
      };

  TenantFeatures write(TenantFeatures f, bool v) => switch (this) {
        quickSale => f.copyWith(quickSale: v),
        stock => f.copyWith(stock: v),
        presetCatalog => f.copyWith(presetCatalog: v),
        expiryBatch => f.copyWith(expiryBatch: v),
        serialWarranty => f.copyWith(serialWarranty: v),
        variants => f.copyWith(variants: v),
        decimalQty => f.copyWith(decimalQty: v),
        quotation => f.copyWith(quotation: v),
        serviceItems => f.copyWith(serviceItems: v),
      };
}
