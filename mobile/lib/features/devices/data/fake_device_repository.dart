import '../../../core/utils/ids.dart';
import '../domain/device.dart';
import 'device_repository.dart';

class FakeDeviceRepository implements DeviceRepository {
  FakeDeviceRepository({required String tenantId, String code = 'A', int lastSeq = 1032}) {
    final t = nowUtc();
    _device = Device(id: newId(), tenantId: tenantId, code: code, lastSeq: lastSeq, createdAt: t, updatedAt: t);
  }

  late Device _device;

  @override
  Device current() => _device;

  @override
  String issueReceiptNo() {
    _device = _device.copyWith(lastSeq: _device.lastSeq + 1, updatedAt: nowUtc());
    return formatReceiptNo(_device.code, _device.lastSeq);
  }
}
