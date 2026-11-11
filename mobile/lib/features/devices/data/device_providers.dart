import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device.dart';
import 'device_repository.dart';

class DeviceNotifier extends Notifier<Device> {
  DeviceRepository get _repo => ref.read(deviceRepositoryProvider);

  @override
  Device build() => _repo.current();

  String issueReceiptNo() {
    final no = _repo.issueReceiptNo();
    state = _repo.current();
    return no;
  }
}

final deviceProvider = NotifierProvider<DeviceNotifier, Device>(DeviceNotifier.new);
