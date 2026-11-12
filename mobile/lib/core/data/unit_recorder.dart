import 'dart:async';

import 'unit_of_work.dart';

/// Collects the rows written inside one unit of work, keyed by server table
/// name (`products`, `saleLines`, …) in the JSON shape of `/sync/push`.
///
/// The active recorder lives in a zone value set by the Drift unit of work;
/// Drift repositories call [UnitRecorder.require] before every write, so a
/// write outside a unit of work (which would never be pushed) fails loudly.
class UnitRecorder {
  UnitRecorder(this.kind);

  final UnitKind kind;
  final _tables = <String, Map<String, Map<String, Object?>>>{};

  static final Object _zoneKey = Object();

  /// The recorder of the unit of work this code runs in, if any.
  static UnitRecorder? get current => Zone.current[_zoneKey] as UnitRecorder?;

  /// The current recorder; throws if called outside a unit of work.
  static UnitRecorder require() =>
      current ??
      (throw StateError('Repository write outside a unit of work: wrap it in UnitOfWork.run(kind, …) '
          'so it is recorded in the outbox and pushed.'));

  /// Runs [body] with this recorder as [current].
  R runWith<R>(R Function() body) => runZoned(body, zoneValues: {_zoneKey: this});

  /// Records [row] of [table]. A row written twice in one unit (same id, or
  /// same featureKey for tenantFeatures) is merged, later fields winning.
  void record(String table, Map<String, Object?> row) {
    final key = (row['id'] ?? row['featureKey'])?.toString();
    if (key == null) throw ArgumentError('Row of $table has neither id nor featureKey');
    final rows = _tables.putIfAbsent(table, () => {});
    rows[key] = {...?rows[key], ...row};
  }

  bool get isEmpty => _tables.isEmpty;

  /// `{"sales": [...], "saleLines": [...], ...}` in first-recorded order.
  Map<String, List<Map<String, Object?>>> get rows => {
        for (final e in _tables.entries) e.key: [...e.value.values],
      };
}
