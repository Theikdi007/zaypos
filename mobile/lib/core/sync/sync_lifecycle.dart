import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_engine.dart';
import 'sync_limits.dart';
import 'sync_providers.dart';

/// When sync runs (docs/mobile/phase3-sync.md §5.1): as soon as the shop is
/// unlocked, every 5 minutes while in the foreground, on returning to the
/// foreground, and when the network comes back. (Committed units schedule
/// their own sync, 2 s later; pull-to-refresh and Settings call it too.)
/// No background sync in v1.
class SyncLifecycle extends ConsumerStatefulWidget {
  const SyncLifecycle({super.key, required this.child, this.interval = const Duration(minutes: 5)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<SyncLifecycle> createState() => _SyncLifecycleState();
}

class _SyncLifecycleState extends ConsumerState<SyncLifecycle> {
  late final AppLifecycleListener _life;
  StreamSubscription<bool>? _net;
  Timer? _timer;
  bool _foreground = true;

  SyncEngine get _engine => ref.read(syncEngineProvider);

  void _kick() => unawaited(_engine.syncNow());

  void _startTimer() {
    _timer?.cancel();
    if (!_foreground || !_engine.enabled) return;
    _timer = Timer.periodic(widget.interval, (_) => _kick());
  }

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        _kick();
        _startTimer();
      },
      onHide: () {
        _foreground = false;
        _timer?.cancel();
      },
    );
    var wasOnline = true;
    _net = ref.read(connectivityProvider).listen((online) {
      if (online && !wasOnline) _kick();
      wasOnline = online;
    }, onError: (Object _) {});
    // A new engine = signed in / unlocked a shop: sync now, then on the timer.
    // The form rules (/sync/limits) are refreshed once per unlock (§1.5).
    ref.listenManual<SyncEngine>(syncEngineProvider, (_, engine) {
      if (engine.enabled) {
        _kick();
        unawaited(ref.read(syncLimitsProvider.notifier).refresh());
      }
      _startTimer();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_net?.cancel());
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
