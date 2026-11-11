import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/features/sales/application/checkout_service.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

/// Container wired exactly like the app (fake repositories).
ProviderContainer makeContainer() => ProviderContainer(overrides: fakeRepositoryOverrides);

/// Loads the bundled fonts so layout tests measure real Myanmar glyphs
/// (the default test font draws every glyph as a full-em square).
Future<void> loadAppFonts() async {
  for (final (family, file) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('NotoSansMyanmar', 'assets/fonts/NotoSansMyanmar-Variable.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

/// Sale line draft for tests.
SaleLineDraft draft({String? productId, String name = 'x', int qtyMilli = 1000, int price = 100, int cost = 0}) => (
      productId: productId,
      variantId: null,
      batchId: null,
      serialId: null,
      name: name,
      qtyMilli: qtyMilli,
      price: price,
      cost: cost,
    );

/// Checks out through the real CheckoutService.
Future<Sale> sell(ProviderContainer c, List<SaleLineDraft> lines,
        {PaymentMethod method = PaymentMethod.cash, String? customerId, int? received}) =>
    c.read(checkoutServiceProvider).checkout(
          CheckoutRequest(lines: lines, method: method, customerId: customerId, received: received),
        );

/// Latest value of an async (stream-backed) provider: subscribes, lets the
/// fake streams deliver, then returns the current data (throws on error).
Future<T> val<T>(ProviderContainer c, ProviderListenable<AsyncValue<T>> p) async {
  final sub = c.listen<AsyncValue<T>>(p, (_, _) {});
  try {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final v = sub.read();
    if (v.hasError) throw v.error!;
    return v.requireValue;
  } finally {
    sub.close();
  }
}
