import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device.dart';
import 'device_repository.dart';

/// Read side for this device (receipt numbers are issued by CheckoutService).
class DeviceNotifier extends Notifier<Device> {
  DeviceRepository get _repo => ref.read(deviceRepositoryProvider);

  @override
  Device build() => _repo.current();

  void refresh() => state = _repo.current();
}

final deviceProvider = NotifierProvider<DeviceNotifier, Device>(DeviceNotifier.new);
