import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/sync/sync_api.dart';

/// Records pushes and pulls; answers from programmable queues.
class FakeSyncApi implements SyncApi {
  final pushes = <List<PushUnit>>[];
  final pushDeviceIds = <String>[];
  final pullCursors = <String>[];
  final resolved = <String>[];

  /// Outcome per pushed unit (default: applied).
  UnitOutcome Function(PushUnit unit) outcome = (_) => UnitOutcome.applied;
  String rejectReason = 'products.name is longer than 120 characters.';

  /// Thrown by the next pushes, one per call (null entries = succeed).
  final pushErrors = <ApiError?>[];

  /// Pages served in order; when empty, an empty page with the last cursor.
  final pages = <PullPage>[];

  /// Thrown by the pull with this 0-based index (counted over all pulls).
  final pullErrors = <int, ApiError>{};

  Duration delay = Duration.zero;
  Map<String, dynamic> Function(String id)? resolveAnswer;

  String _lastCursor = '0';

  @override
  Future<List<UnitResult>> push(String deviceId, List<PushUnit> units) async {
    await Future<void>.delayed(delay);
    pushes.add(units);
    pushDeviceIds.add(deviceId);
    if (pushErrors.isNotEmpty) {
      final e = pushErrors.removeAt(0);
      if (e != null) throw e;
    }
    return [
      for (final u in units)
        switch (outcome(u)) {
          UnitOutcome.rejected => UnitResult(unitId: u.unitId, outcome: UnitOutcome.rejected, reason: rejectReason),
          final o => UnitResult(unitId: u.unitId, outcome: o),
        },
    ];
  }

  @override
  Future<PullPage> pull(String cursor, {int limit = 500}) async {
    await Future<void>.delayed(delay);
    final index = pullCursors.length;
    pullCursors.add(cursor);
    final e = pullErrors[index];
    if (e != null) throw e;
    if (pages.isEmpty) return PullPage(changes: const {}, cursor: _lastCursor, hasMore: false);
    final p = pages.removeAt(0);
    _lastCursor = p.cursor;
    return p;
  }

  @override
  Future<Map<String, dynamic>> resolveIssue(String id) async {
    resolved.add(id);
    return resolveAnswer!(id);
  }
}

/// A pull page of [changes] (table → rows).
PullPage page(Map<String, List<Map<String, dynamic>>> changes, {required String cursor, bool hasMore = false}) =>
    PullPage(changes: changes, cursor: cursor, hasMore: hasMore);
