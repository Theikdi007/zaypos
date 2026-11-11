import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';

/// Signed-in shop session (fake).
class ShopSession {
  const ShopSession({required this.tenantId, required this.shopName, required this.startedAt});

  /// Tenant (shop) id stamped on every entity.
  final String tenantId;
  final String shopName;

  /// When this app session started (UTC).
  final DateTime startedAt;

  ShopSession copyWith({String? shopName}) =>
      ShopSession(tenantId: tenantId, shopName: shopName ?? this.shopName, startedAt: startedAt);
}

class SessionNotifier extends Notifier<ShopSession> {
  @override
  ShopSession build() => ShopSession(tenantId: newId(), shopName: 'ရွှေဝါ ကုန်စုံဆိုင်', startedAt: nowUtc());

  void setShopName(String name) {
    if (name.trim().isNotEmpty) state = state.copyWith(shopName: name.trim());
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, ShopSession>(SessionNotifier.new);

/// Shortcut for the current tenant id.
final tenantIdProvider = Provider<String>((ref) => ref.watch(sessionProvider.select((s) => s.tenantId)));
