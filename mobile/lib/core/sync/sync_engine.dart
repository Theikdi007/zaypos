import 'dart:async';
import 'dart:developer' as developer;

import '../api/api_error.dart';
import 'sync_api.dart';
import 'sync_store.dart';

/// What the sync card / chip says when a cycle fails (Burmese only — the raw error is logged, BUG-30).
abstract final class SyncMessages {
  static const unreadable = 'ဆာဗာက ပို့တဲ့ ဒေတာကို ဖတ်မရပါ။ အက်ပ်ကို အပ်ဒိတ်လုပ်ပါ (သို့) အကူအညီဌာနကို ဆက်သွယ်ပါ။';
  static const failed = 'Sync လုပ်လို့ မရသေးပါ။ ခဏနေမှ ပြန်ကြိုးစားပါ (သို့) အကူအညီဌာနကို ဆက်သွယ်ပါ။';
}

/// What the sync UI shows (chip, Settings, first-download screen).
class SyncSnapshot {
  const SyncSnapshot({
    this.enabled = true,
    this.running = false,
    this.online = true,
    this.lastSyncAt,
    this.lastError,
    this.downloadedRows,
  });

  /// false = demo shop / signed out: nothing syncs.
  final bool enabled;
  final bool running;

  /// false after a network failure, until a call succeeds again.
  final bool online;

  /// Last completed cycle (UTC).
  final DateTime? lastSyncAt;

  /// Burmese message of the last failure (null after a clean cycle).
  final String? lastError;

  /// Rows merged so far during the first full download (§5.4); null otherwise.
  final int? downloadedRows;

  SyncSnapshot copyWith({
    bool? running,
    bool? online,
    DateTime? lastSyncAt,
    String? Function()? lastError,
    int? Function()? downloadedRows,
  }) =>
      SyncSnapshot(
        enabled: enabled,
        running: running ?? this.running,
        online: online ?? this.online,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: lastError != null ? lastError() : this.lastError,
        downloadedRows: downloadedRows != null ? downloadedRows() : this.downloadedRows,
      );
}

/// Push-then-pull sync (docs/mobile/phase3-sync.md §5). One cycle at a time.
class SyncEngine {
  SyncEngine({
    required this.api,
    required this.store,
    required this.deviceId,
    this.onSessionEnded,
    this.onInitialSyncDone,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 2),
    this.pullLimit = 500,
  })  : clock = clock ?? (() => DateTime.now().toUtc()),
        enabled = true {
    _activeAt = this.clock(); // a just-unlocked shop counts as active (§5.1)
  }

  /// Demo shop / signed out: every call is a no-op.
  SyncEngine.disabled()
      : api = null,
        store = null,
        deviceId = '',
        onSessionEnded = null,
        onInitialSyncDone = null,
        clock = (() => DateTime.now().toUtc()),
        debounce = Duration.zero,
        pullLimit = 0,
        enabled = false {
    _snapshot = const SyncSnapshot(enabled: false);
  }

  final SyncApi? api;
  final SyncStore? store;
  final String deviceId;
  final bool enabled;

  /// The server refused this device (`device_revoked`): sign out, keep data.
  final Future<void> Function(String code)? onSessionEnded;

  /// The first full download finished (the app may open, §5.4).
  final void Function()? onInitialSyncDone;
  final DateTime Function() clock;
  final Duration debounce;
  final int pullLimit;

  /// Wait before pushing again after the n-th consecutive failure (§5.2).
  static const backoff = [Duration(seconds: 5), Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 10)];

  static Duration backoffFor(int failures) => backoff[(failures.clamp(1, backoff.length)) - 1];

  /// Timer and resume pulls are skipped when a recent pull already covered them (§5.1, fewer requests through the
  /// edge proxy). The ages are a little under the 5 / 15 min marks so a tick that lands right on schedule still pulls.
  static const activePullAge = Duration(minutes: 4, seconds: 30);
  static const idlePullAge = Duration(minutes: 14, seconds: 30);

  /// No committed unit, resume or manual sync for this long = idle.
  static const idleAfter = Duration(minutes: 30);

  /// Returning to the foreground pulls only if the last pull is older than this.
  static const resumePullAge = Duration(seconds: 60);

  SyncSnapshot _snapshot = const SyncSnapshot();
  final _changes = StreamController<SyncSnapshot>.broadcast();
  Future<void>? _running;
  bool _again = false;
  Timer? _debounceTimer;
  int _failures = 0;
  DateTime? _pushAfter;
  bool _disposed = false;

  /// Start of the last cycle whose pull completed (null = none yet). The start, not the end: what the server had
  /// after that moment may not have been pulled.
  DateTime? _pulledAt;

  /// Last local change (committed unit), resume or manual sync.
  DateTime? _activeAt;

  SyncSnapshot get snapshot => _snapshot;
  Stream<SyncSnapshot> get changes => _changes.stream;

  /// When automatic pushes resume after failures (null = now).
  DateTime? get pushAfter => _pushAfter;

  /// No local change, resume or manual sync for [idleAfter].
  bool get idle => _activeAt == null || !clock().isBefore(_activeAt!.add(idleAfter));

  /// The 5-minute foreground timer (§5.1): every tick while active, every third tick (15 min) when idle, and only
  /// when no other cycle pulled in the meantime. Units waiting to go up always run (unless backing off).
  Future<void> onTimer() => _syncIfDue(idle ? idlePullAge : activePullAge);

  /// Back in the foreground: counts as activity; pulls unless the last pull is under a minute old.
  Future<void> onResume() {
    if (!enabled || _disposed) return Future.value();
    _activeAt = clock();
    return _syncIfDue(resumePullAge);
  }

  Future<void> _syncIfDue(Duration maxAge) async {
    if (!enabled || _disposed) return;
    final pulled = _pulledAt;
    final stale = pulled == null || !clock().isBefore(pulled.add(maxAge));
    if (stale || await _pushDue()) await syncNow();
  }

  /// A unit is waiting to go up and the backoff (if any) is over.
  Future<bool> _pushDue() async {
    if (_pushAfter != null && clock().isBefore(_pushAfter!)) return false;
    return (await store!.nextBatch(1)).isNotEmpty;
  }

  void _emit(SyncSnapshot s) {
    _snapshot = s;
    if (!_disposed) _changes.add(s);
  }

  /// Runs a cycle now, or joins the running one. A trigger that arrives while
  /// a cycle runs queues ONE more cycle (so a just-committed unit is not left
  /// waiting for the next timer). [manual] ignores the backoff.
  Future<void> syncNow({bool manual = false}) {
    if (!enabled || _disposed) return Future.value();
    if (manual) {
      _pushAfter = null;
      _activeAt = clock();
    }
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _loop(manual);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _loop(bool manual) async {
    do {
      _again = false;
      await _cycle(manual);
      manual = false;
    } while (_again && !_disposed);
  }

  /// 2 s after a committed unit (debounced, §5.1).
  void scheduleSoon() {
    if (!enabled || _disposed) return;
    _activeAt = clock();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  Future<void> _cycle(bool manual) async {
    final store = this.store!;
    final started = clock();
    _emit(_snapshot.copyWith(running: true));
    String? error;
    var online = true;
    try {
      final initial = !await store.initialSyncDone();
      // An empty phone never pushes on top of a shop it hasn't seen (§5.4).
      if (!initial) {
        final pushError = await _push(manual);
        if (pushError != null) {
          error = pushError.message;
          online = !pushError.isNetwork;
        }
      }
      if (online) {
        await _pull(initial: initial);
        _pulledAt = started;
        if (initial) {
          await store.markInitialSyncDone();
          onInitialSyncDone?.call();
          // The shop has been seen now: send what was recorded meanwhile
          // (e.g. the preset catalog of a new shop) in the same cycle.
          final pushError = await _push(manual);
          if (pushError != null) {
            error = pushError.message;
            online = !pushError.isNetwork;
          }
        }
      }
    } on ApiError catch (e) {
      error = e.message;
      online = !e.isNetwork;
      if (e.status == 403 && e.code == 'device_revoked') await onSessionEnded?.call(e.code);
    } on Object catch (e, st) {
      // e.g. a pulled row this app cannot store (FormatException): that page
      // was rolled back, the cursor stays; report it, never crash the trigger.
      // BUG-30: the user sees Burmese only; the raw error goes to the log.
      error = e is FormatException ? SyncMessages.unreadable : SyncMessages.failed;
      developer.log('sync cycle failed', name: 'zaypos.sync', error: e, stackTrace: st);
    }
    _emit(_snapshot.copyWith(
      running: false,
      online: online,
      lastSyncAt: error == null ? clock() : null,
      lastError: () => error,
      downloadedRows: () => null,
    ));
  }

  /// Pushes until the outbox is empty or blocked. Returns the failure that
  /// stopped it (network / server); a revoked device rethrows.
  Future<ApiError?> _push(bool manual) async {
    final store = this.store!;
    if (!manual && _pushAfter != null && clock().isBefore(_pushAfter!)) return null; // backing off
    while (true) {
      final batch = await store.nextBatch();
      if (batch.isEmpty) return null;
      final PushResult result;
      try {
        result = await api!.push(deviceId, [
          for (final o in batch)
            PushUnit(
              unitId: o.unitId,
              kind: o.kind,
              clientTime: DateTime.fromMillisecondsSinceEpoch(o.clientTime, isUtc: true),
              rows: SyncStore.rowsOf(o),
            ),
        ]);
      } on ApiError catch (e) {
        if (e.status == 403 && e.code == 'device_revoked') rethrow;
        if (e.status == 401) rethrow; // session already ended by the refresh interceptor
        _failures++;
        _pushAfter = clock().add(backoffFor(_failures));
        await store.markFailed(batch, e.message);
        return e;
      }
      _failures = 0;
      _pushAfter = null;
      // The server clamps future edit times to its clock + 5 min (README §3.3); do the
      // same to this phone's copy so later edits from other phones are not refused (BUG-5).
      final blocked = await store.applyResults(batch, result.results,
          editTimeLimit: (result.serverTime ?? clock()).add(SyncStore.maxClockAhead));
      if (blocked) return null; // blocked by a rejected unit
    }
  }

  Future<void> _pull({required bool initial}) async {
    final store = this.store!;
    var merged = 0;
    if (initial) _emit(_snapshot.copyWith(downloadedRows: () => 0));
    while (true) {
      final page = await api!.pull(await store.cursor(), limit: pullLimit);
      merged += await store.mergePage(page);
      if (initial) _emit(_snapshot.copyWith(downloadedRows: () => merged));
      if (!page.hasMore) return;
    }
  }

  /// Owner marks a sync issue reviewed; the returned row is merged at once.
  Future<void> resolveIssue(String id) async {
    if (!enabled) return;
    final row = await api!.resolveIssue(id);
    await store!.mergeRow('syncIssues', row);
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    unawaited(_changes.close());
  }
}
