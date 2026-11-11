import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "ရိုးရှင်း mode" toggle (UI-only for this phase; not a tenant feature flag).
class SimpleModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final simpleModeProvider = NotifierProvider<SimpleModeNotifier, bool>(SimpleModeNotifier.new);
