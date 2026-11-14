import '../../../core/data/unit_recorder.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/mappers.dart';
import '../../../core/sync/wire.dart';
import '../../../core/utils/ids.dart';
import '../domain/device.dart';
import 'device_repository.dart';

class DriftDeviceRepository implements DeviceRepository {
  DriftDeviceRepository(this.db, {required this.deviceId});
  final AppDatabase db;
  final String deviceId;

  @override
  Stream<Device> watchCurrent() => (db.select(db.devices)..where((d) => d.id.equals(deviceId)))
      .watchSingleOrNull()
      .map((r) => r == null ? throw StateError('Unknown device $deviceId') : deviceFromRow(r));

  /// Advances lastSeq and records this device's row in the same (checkout)
  /// unit, so the server's lastSeq follows (§4).
  @override
  Future<String> issueReceiptNo() async {
    final rec = UnitRecorder.require();
    final current = await (db.select(db.devices)..where((d) => d.id.equals(deviceId))).getSingleOrNull();
    if (current == null) throw StateError('Unknown device $deviceId');
    final updated = current.copyWith(lastSeq: current.lastSeq + 1, updatedAt: nowUtc());
    await db.update(db.devices).replace(updated);
    rec.record(WireTable.devices, deviceWire(updated));
    return formatReceiptNo(updated.code, updated.lastSeq);
  }
}
