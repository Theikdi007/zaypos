import 'dart:async';

import '../api/api_error.dart';
import 'sync_api.dart';
import 'sync_store.dart';

abstract final class SyncMessages {
  static const unreadable = 'Server က ပို့တဲ့ data ကို ဖတ်မရပါ။ App ကို update လုပ်ပါ (သို့) Support ကို ဆက်သွယ်ပါ။';
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
        enabled = true;

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

  SyncSnapshot _snapshot = const SyncSnapshot();
  final _changes = StreamController<SyncSnapshot>.broadcast();
  Future<void>? _running;
  bool _again = false;
  Timer? _debounceTimer;
  int _failures = 0;
  DateTime? _pushAfter;
  bool _disposed = false;

  SyncSnapshot get snapshot => _snapshot;
  Stream<SyncSnapshot> get changes => _changes.stream;

  /// When automatic pushes resume after failures (null = now).
  DateTime? get pushAfter => _pushAfter;

  void _emit(SyncSnapshot s) {
    _snapshot = s;
    if (!_disposed) _changes.add(s);
  }

  /// Runs a cycle now, or joins the running one. A trigger that arrives while
  /// a cycle runs queues ONE more cycle (so a just-committed unit is not left
  /// waiting for the next timer). [manual] ignores the backoff.
  Future<void> syncNow({bool manual = false}) {
    if (!enabled || _disposed) return Future.value();
    if (manual) _pushAfter = null;
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
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  Future<void> _cycle(bool manual) async {
    final store = this.store!;
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
    } on Object catch (e) {
      // e.g. a pulled row this app cannot store (FormatException): that page
      // was rolled back, the cursor stays; report it, never crash the trigger.
      error = '${SyncMessages.unreadable} ($e)';
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
      final List<UnitResult> results;
      try {
        results = await api!.push(deviceId, [
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
      if (await store.applyResults(batch, results)) return null; // blocked by a rejected unit
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
