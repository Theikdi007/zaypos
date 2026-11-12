import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated, time-ordered id (UUID v7). Safe to create offline and
/// merge on sync without collisions.
String newId() => _uuid.v7();

/// Current time in UTC, truncated to whole milliseconds. All entity
/// timestamps are stored in UTC (unix ms locally, ms ISO-8601 on the wire)
/// and only converted to local time for display; truncating here keeps the
/// in-memory value equal to what the database and the server store, so
/// last-writer-wins comparisons are exact.
DateTime nowUtc() => truncateToMs(DateTime.now());

/// [t] in UTC with sub-millisecond precision dropped.
DateTime truncateToMs(DateTime t) => DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
