import '../../../app/fake_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/device.dart';
import 'device_repository.dart';

/// This device: code 'A', last receipt A-1032 (design sample).
Device seedDevice(String tenantId, {String code = 'A', int lastSeq = 1032}) {
  final t = nowUtc();
  return Device(id: newId(), tenantId: tenantId, code: code, lastSeq: lastSeq, createdAt: t, updatedAt: t);
}

class FakeDeviceRepository implements DeviceRepository {
  FakeDeviceRepository(this.db, {required this.deviceId});
  final FakeDatabase db;
  final String deviceId;

  int get _i {
    final i = db.devices.indexWhere((d) => d.id == deviceId);
    if (i < 0) throw StateError('Unknown device $deviceId');
    return i;
  }

  @override
  Device current() => db.devices[_i];

  @override
  String issueReceiptNo() {
    final i = _i;
    final d = db.devices[i].copyWith(lastSeq: db.devices[i].lastSeq + 1, updatedAt: nowUtc());
    db.devices[i] = d;
    return formatReceiptNo(d.code, d.lastSeq);
  }
}
