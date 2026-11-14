import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import 'boot_state.dart';

/// The shop this app is working for (signed in, or the debug demo shop).
/// Signed out: a placeholder with an empty [tenantId] (screens behind the
/// router guard never run then).
class ShopSession {
  const ShopSession({
    required this.tenantId,
    required this.shopName,
    required this.startedAt,
    this.templateId = 'grocery',
    this.userId = '',
    this.phone = '',
    this.role = 'owner',
    this.isDemo = false,
  });

  /// Tenant (shop) id stamped on every entity.
  final String tenantId;
  final String shopName;
  final String templateId;
  final String userId;

  /// E.164.
  final String phone;

  /// `owner` | `staff`.
  final String role;

  /// Debug-only sample shop: never synced.
  final bool isDemo;

  /// When this app session started (UTC).
  final DateTime startedAt;

  bool get isOwner => role == 'owner';
}

class SessionNotifier extends Notifier<ShopSession> {
  static const signedOutShopName = '';

  @override
  ShopSession build() {
    final boot = ref.watch(bootStateProvider);
    final s = boot.session;
    if (s != null) {
      return ShopSession(
        tenantId: s.tenantId,
        shopName: s.shopName,
        templateId: s.templateId,
        userId: s.userId,
        phone: s.phone,
        role: s.role,
        startedAt: nowUtc(),
      );
    }
    // Tests that start unlocked without a session get a fresh in-memory shop.
    if (boot.startUnlocked) return ShopSession(tenantId: newId(), shopName: 'ရွှေဝါ ကုန်စုံဆိုင်', startedAt: nowUtc());
    return ShopSession(tenantId: '', shopName: signedOutShopName, startedAt: nowUtc());
  }

  /// Set by the auth controller on sign-in / sign-out.
  void set(ShopSession session) => state = session;
}

final sessionProvider = NotifierProvider<SessionNotifier, ShopSession>(SessionNotifier.new);

/// Shortcut for the current tenant id.
final tenantIdProvider = Provider<String>((ref) => ref.watch(sessionProvider.select((s) => s.tenantId)));
