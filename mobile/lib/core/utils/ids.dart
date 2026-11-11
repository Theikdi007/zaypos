import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated, time-ordered id (UUID v7). Safe to create offline and
/// merge on sync without collisions.
String newId() => _uuid.v7();

/// Current time in UTC. All entity timestamps are stored in UTC and only
/// converted to local time for display.
DateTime nowUtc() => DateTime.now().toUtc();
