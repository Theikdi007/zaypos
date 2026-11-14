import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated, time-ordered id (UUID v7). Safe to create offline and
/// merge on sync without collisions.
String newId() => _uuid.v7();

/// Deterministic id (UUID v5) for a row that must exist at most once per
/// [key], whichever phone creates it — e.g. the reversal of one payment.
/// Two phones produce the same id, and the server keeps the first.
String derivedId(String key) => _uuid.v5(Namespace.url.value, 'zaypos:$key');

/// Current time in UTC, truncated to whole milliseconds. All entity
/// timestamps are stored in UTC (unix ms locally, ms ISO-8601 on the wire)
/// and only converted to local time for display; truncating here keeps the
/// in-memory value equal to what the database and the server store, so
/// last-writer-wins comparisons are exact.
DateTime nowUtc() => truncateToMs(DateTime.now());

/// [t] in UTC with sub-millisecond precision dropped.
DateTime truncateToMs(DateTime t) => DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
