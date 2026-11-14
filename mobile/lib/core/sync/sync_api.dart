import 'package:dio/dio.dart';

import '../api/api_error.dart';

/// One outbox unit on the wire (`POST /sync/push`).
class PushUnit {
  const PushUnit({required this.unitId, required this.kind, required this.clientTime, required this.rows});
  final String unitId;
  final String kind;
  final DateTime clientTime;
  final Map<String, dynamic> rows;

  Map<String, Object?> toJson() =>
      {'unitId': unitId, 'kind': kind, 'clientTime': clientTime.toUtc().toIso8601String(), 'rows': rows};
}

enum UnitOutcome { applied, skipped, rejected }

class UnitResult {
  const UnitResult({required this.unitId, required this.outcome, this.reason, this.issues = const []});
  final String unitId;
  final UnitOutcome outcome;
  final String? reason;

  /// Server SyncIssueKind names raised by this unit.
  final List<String> issues;

  factory UnitResult.fromJson(Map<String, dynamic> j) => UnitResult(
        unitId: j['unitId'] as String,
        outcome: UnitOutcome.values.byName(j['outcome'] as String),
        reason: j['reason'] as String?,
        issues: [for (final i in (j['issues'] as List? ?? const [])) i as String],
      );
}

/// One `/sync/pull` page: `changes` maps a server table name to its rows.
class PullPage {
  const PullPage({required this.changes, required this.cursor, required this.hasMore});
  final Map<String, List<Map<String, dynamic>>> changes;
  final String cursor;
  final bool hasMore;

  int get rowCount => changes.values.fold(0, (a, rows) => a + rows.length);

  factory PullPage.fromJson(Map<String, dynamic> j) => PullPage(
        changes: {
          for (final e in (j['changes'] as Map<String, dynamic>).entries)
            e.key: [for (final r in e.value as List) (r as Map).cast<String, dynamic>()],
        },
        cursor: j['cursor'] as String,
        hasMore: j['hasMore'] as bool,
      );
}

/// `/api/v1/sync/*`. Throws [ApiError].
abstract interface class SyncApi {
  Future<List<UnitResult>> push(String deviceId, List<PushUnit> units);
  Future<PullPage> pull(String cursor, {int limit = 500});

  /// Owner only. Returns the updated syncIssues row.
  Future<Map<String, dynamic>> resolveIssue(String id);
}

class DioSyncApi implements SyncApi {
  DioSyncApi(this.dio);

  /// Authenticated dio (token refresh interceptor).
  final Dio dio;

  Future<T> _call<T>(Future<Response<dynamic>> Function() request, T Function(Map<String, dynamic>) parse) async {
    try {
      final r = await request();
      return parse((r.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw e.error is ApiError ? e.error! as ApiError : ApiError.fromDio(e);
    }
  }

  @override
  Future<List<UnitResult>> push(String deviceId, List<PushUnit> units) => _call(
        () => dio.post<dynamic>('/api/v1/sync/push',
            data: {'deviceId': deviceId, 'units': [for (final u in units) u.toJson()]}),
        (j) => [for (final r in j['results'] as List) UnitResult.fromJson((r as Map).cast<String, dynamic>())],
      );

  @override
  Future<PullPage> pull(String cursor, {int limit = 500}) => _call(
        () => dio.get<dynamic>('/api/v1/sync/pull', queryParameters: {'cursor': cursor, 'limit': limit}),
        PullPage.fromJson,
      );

  @override
  Future<Map<String, dynamic>> resolveIssue(String id) =>
      _call(() => dio.post<dynamic>('/api/v1/sync/issues/$id/resolve'), (j) => j);
}
