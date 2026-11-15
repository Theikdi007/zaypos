// QA round 9 — found while running m/qa/live_qa_round9_test.dart: a pulled row whose field became NULL on the server did
// not clear the phone's copy (SyncIssues.Data blanked on the server, phone A still had the old data after a pull).
// sync_store.dart _merge uses `insertOnConflictUpdate(<data class>)`; this checks whether a NULL that arrives in a pull
// overwrites the local value — for an issue (server is the truth, phase3-sync.md §5.3) and for a product edited on another
// phone (last-writer-wins: the newer pulled row replaces the local one, README / phase3-sync.md §5.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/sync/sync_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';

import '../drift_helpers.dart';
import '../fake_sync_api.dart';

void main() {
  test('TC-SYNC-NEW-14 pulled NULLs replace local values: a product whose barcode / wholesale price was cleared on another phone, an '
      'issue whose data is null', () async {
    final db = memoryDb();
    addTearDown(db.close);
    const tid = 't-r9';
    final store = SyncStore(db, tenantId: tid, deviceId: 'dev-a');
    final pid = newId(), iid = newId();
    Map<String, dynamic> product(DateTime at, {String? barcode, int? wholesale}) => {
          'id': pid, 'tenantId': tid, 'name': 'QA r9 soap', 'category': 'x', 'unit': 'ခု', 'cost': 100, 'price': 150,
          'barcode': barcode, 'wholesalePrice': wholesale, 'lowAlertMilli': 0, 'tint': 4292533246, 'initial': 'Q',
          'createdAt': '2026-11-14T08:00:00Z', 'updatedAt': at.toIso8601String(), 'deletedAt': null,
        };
    Map<String, dynamic> issue(DateTime at, String? data) => {
          'id': iid, 'tenantId': tid, 'kind': 'duplicateBarcode', 'entityTable': 'Products', 'entityId': pid, 'detail': 'x',
          'data': data, 'deviceId': null, 'resolvedAt': null,
          'createdAt': '2026-11-14T08:00:00Z', 'updatedAt': at.toIso8601String(), 'deletedAt': null,
        };
    final t1 = DateTime.utc(2026, 11, 14, 9), t2 = DateTime.utc(2026, 11, 14, 10);
    await store.mergePage(page({
      'products': [product(t1, barcode: '8850000099500', wholesale: 140)],
      'syncIssues': [issue(t1, '{"barcode":"8850000099500"}')],
    }, cursor: '01'));
    final before = await db.select(db.products).getSingle();
    expect((before.barcode, before.wholesalePrice), ('8850000099500', 140));

    // phone B cleared the barcode and the wholesale price (a newer edit); the server's issue row has data null
    await store.mergePage(page({
      'products': [product(t2)],
      'syncIssues': [issue(t2, null)],
    }, cursor: '02'));
    final after = await db.select(db.products).getSingle();
    final i = await db.select(db.syncIssues).getSingle();
    expect(after.updatedAt, t2, reason: 'the newer row was taken');
    expect({'barcode': after.barcode, 'wholesalePrice': after.wholesalePrice, 'issue.data': i.data},
        {'barcode': null, 'wholesalePrice': null, 'issue.data': null},
        reason: 'a field cleared on another phone must be cleared here too (last-writer-wins takes the whole row)');
  });
}
