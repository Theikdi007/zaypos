import 'dart:convert';

import '../data/unit_of_work.dart';
import '../data/unit_recorder.dart';
import '../utils/ids.dart';
import 'app_database.dart';

/// Drift unit of work (docs/mobile/phase3-sync.md §4):
/// 1. opens `db.transaction`,
/// 2. runs the body with a [UnitRecorder] in its zone (every Drift repository
///    write records its row there),
/// 3. inserts ONE outbox row with every recorded row, in the same transaction
///    — if the body throws, neither the rows nor the outbox row are written,
/// 4. after commit, calls [onCommitted] (the sync engine, debounced, Step 3).
class DriftUnitOfWork implements UnitOfWork {
  DriftUnitOfWork(this.db, {this.onCommitted});

  final AppDatabase db;
  void Function(UnitKind kind)? onCommitted;

  @override
  Future<T> run<T>(UnitKind kind, Future<T> Function() body) async {
    if (UnitRecorder.current != null) return body(); // nested: join the outer unit

    final recorder = UnitRecorder(kind);
    final result = await db.transaction(() => recorder.runWith(() async {
          final r = await body();
          if (!recorder.isEmpty) {
            await db.into(db.outbox).insert(OutboxCompanion.insert(
                  unitId: newId(),
                  kind: kind.name,
                  rowsJson: jsonEncode(recorder.rows),
                  clientTime: nowUtc().millisecondsSinceEpoch,
                ));
          }
          return r;
        }));
    if (!recorder.isEmpty) onCommitted?.call(kind);
    return result;
  }
}
