import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/boot_state.dart';
import '../../features/auth/data/session.dart';
import '../api/api_config.dart';
import '../data/unit_of_work.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';
import '../db/drift_unit_of_work.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'sync_store.dart';

final syncApiProvider = Provider<SyncApi>((ref) => DioSyncApi(ref.watch(apiDioProvider)));

/// true while the network is reachable (Wi-Fi / mobile / ethernet …).
/// Tests override with a controllable stream.
final connectivityProvider = Provider<Stream<bool>>((_) => Connectivity()
    .onConnectivityChanged
    .map((r) => r.any((c) => c != ConnectivityResult.none))
    .distinct());

/// The first full download for this shop finished (§5.4). Until then the
/// app shows the download screen instead of the shop.
class FirstSyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    final boot = ref.watch(bootStateProvider);
    return boot.startUnlocked || boot.initialSyncDone;
  }

  void set(bool done) => state = done;
}

final firstSyncDoneProvider = NotifierProvider<FirstSyncNotifier, bool>(FirstSyncNotifier.new);

/// The sync engine of the signed-in, unlocked shop. Disabled for the demo
/// shop, when signed out or locked. Committed units schedule a sync 2 s later.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final session = ref.watch(sessionProvider);
  final status = ref.watch(authControllerProvider.select((s) => s.status));
  if (session.isDemo || session.tenantId.isEmpty || status != AuthStatus.unlocked) return SyncEngine.disabled();

  final db = ref.watch(appDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final engine = SyncEngine(
    api: ref.watch(syncApiProvider),
    store: SyncStore(db, tenantId: session.tenantId, deviceId: deviceId),
    deviceId: deviceId,
    onSessionEnded: (code) => ref.read(authControllerProvider.notifier).sessionEnded(code),
    onInitialSyncDone: () => ref.read(firstSyncDoneProvider.notifier).set(true),
    clock: ref.watch(clockProvider),
  );
  final uow = ref.watch(unitOfWorkProvider);
  if (uow is DriftUnitOfWork) {
    uow.onCommitted = (_) => engine.scheduleSoon();
    ref.onDispose(() => uow.onCommitted = null);
  }
  ref.onDispose(engine.dispose);
  return engine;
});

final syncSnapshotProvider = StreamProvider<SyncSnapshot>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.snapshot;
  yield* engine.changes;
});

final outboxCountsProvider = StreamProvider<OutboxCounts>(
    (ref) => ref.watch(syncEngineProvider).store?.watchCounts() ?? Stream.value(const OutboxCounts()));

final rejectedUnitsProvider = StreamProvider<List<OutboxRow>>(
    (ref) => ref.watch(syncEngineProvider).store?.watchRejected() ?? Stream.value(const []));

final openIssuesProvider = StreamProvider<List<SyncIssueRow>>(
    (ref) => ref.watch(syncEngineProvider).store?.watchOpenIssues() ?? Stream.value(const []));

/// Dashboard chip (§7): synced / n waiting / offline / sync problem.
enum SyncChipKind { hidden, synced, waiting, offline, problem }

class SyncChipState {
  const SyncChipState(this.kind, {this.waiting = 0, this.problems = 0});
  final SyncChipKind kind;
  final int waiting;
  final int problems;
}

final syncChipProvider = Provider<SyncChipState>((ref) {
  final snap = ref.watch(syncSnapshotProvider).value ?? ref.watch(syncEngineProvider).snapshot;
  if (!snap.enabled) return const SyncChipState(SyncChipKind.hidden);
  final counts = ref.watch(outboxCountsProvider).value ?? const OutboxCounts();
  final issues = ref.watch(openIssuesProvider).value?.length ?? 0;
  final problems = counts.rejected + issues;
  if (problems > 0) return SyncChipState(SyncChipKind.problem, waiting: counts.pending, problems: problems);
  if (!snap.online) return SyncChipState(SyncChipKind.offline, waiting: counts.pending);
  if (counts.pending > 0 || snap.running) return SyncChipState(SyncChipKind.waiting, waiting: counts.pending);
  return const SyncChipState(SyncChipKind.synced);
});
