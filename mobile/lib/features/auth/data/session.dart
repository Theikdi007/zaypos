import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';

/// Signed-in shop session. Step 1: the local tenant from the database
/// bootstrap (lib/app/local_bootstrap.dart); Step 2 fills it from sign-in.
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
  SessionNotifier({this.tenantId, this.shopName});

  /// Initial values (composition root); null = a fresh in-memory tenant (tests).
  final String? tenantId;
  final String? shopName;

  static const defaultShopName = 'ရွှေဝါ ကုန်စုံဆိုင်';

  @override
  ShopSession build() =>
      ShopSession(tenantId: tenantId ?? newId(), shopName: shopName ?? defaultShopName, startedAt: nowUtc());

  void setShopName(String name) {
    if (name.trim().isNotEmpty) state = state.copyWith(shopName: name.trim());
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, ShopSession>(SessionNotifier.new);

/// Shortcut for the current tenant id.
final tenantIdProvider = Provider<String>((ref) => ref.watch(sessionProvider.select((s) => s.tenantId)));
