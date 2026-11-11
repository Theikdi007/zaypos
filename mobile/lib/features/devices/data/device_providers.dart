import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device.dart';
import 'device_repository.dart';

/// This device (live) — e.g. for the next receipt number in the POS header.
final deviceProvider = StreamProvider<Device>((ref) => ref.watch(deviceRepositoryProvider).watchCurrent());
