import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/sync/sync_engine.dart';
import 'package:zaypos_app/core/sync/sync_lifecycle.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';

import 'fake_sync_api.dart';

/// Records which trigger the lifecycle used; never talks to a server.
class _RecordingEngine extends SyncEngine {
  _RecordingEngine() : super(api: FakeSyncApi(), store: null, deviceId: 'd');

  final calls = <String>[];

  @override
  Future<void> syncNow({bool manual = false}) async => calls.add(manual ? 'manual' : 'now');

  @override
  Future<void> onTimer() async => calls.add('timer');

  @override
  Future<void> onResume() async => calls.add('resume');
}

class _NoNetworkLimits extends SyncLimitsNotifier {
  @override
  Future<void> refresh() async {}
}

void main() {
  late _RecordingEngine engine;
  late StreamController<bool> net;

  Future<void> pumpLifecycle(WidgetTester tester) async {
    engine = _RecordingEngine();
    net = StreamController<bool>.broadcast();
    addTearDown(net.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        syncEngineProvider.overrideWithValue(engine),
        connectivityProvider.overrideWithValue(net.stream),
        syncLimitsProvider.overrideWith(_NoNetworkLimits.new),
      ],
      child: const SyncLifecycle(child: SizedBox()),
    ));
  }

  testWidgets('unlock syncs at once; the 5-minute timer goes through onTimer (which may skip the pull)', (tester) async {
    await pumpLifecycle(tester);
    expect(engine.calls, ['now'], reason: 'a new engine = unlocked: always sync');

    await tester.pump(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(engine.calls, ['now', 'timer', 'timer']);
  });

  testWidgets('back in the foreground goes through onResume; network-back always syncs', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // the test binding starts with none
    await pumpLifecycle(tester);
    engine.calls.clear();

    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(minutes: 10));
    expect(engine.calls, isEmpty, reason: 'no timer in the background');
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(engine.calls, ['resume']);

    engine.calls.clear();
    net.add(false);
    await tester.pump();
    net.add(true);
    await tester.pump();
    expect(engine.calls, ['now']);
  });
}
