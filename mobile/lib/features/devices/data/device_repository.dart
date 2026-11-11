import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device.dart';

abstract interface class DeviceRepository {
  /// This device (registered on first launch).
  Stream<Device> watchCurrent();

  /// Advances this device's sequence and returns the new receipt number
  /// ("A-1033"). Run inside the checkout unit of work.
  Future<String> issueReceiptNo();
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final deviceRepositoryProvider = Provider<DeviceRepository>(
  (_) => throw UnimplementedError('deviceRepositoryProvider must be overridden'),
);
