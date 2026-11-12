import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../auth/application/auth_controller.dart';

/// A phone of the shop as the server lists it (`GET /api/v1/devices`).
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.code,
    this.name,
    required this.lastSeq,
    this.lastSyncAt,
    required this.createdAt,
    required this.isCurrent,
  });

  final String id;

  /// Receipt prefix: 'A', 'B', …
  final String code;
  final String? name;
  final int lastSeq;
  final DateTime? lastSyncAt;
  final DateTime createdAt;

  /// This phone.
  final bool isCurrent;

  factory RemoteDevice.fromJson(Map<String, dynamic> j) => RemoteDevice(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String?,
        lastSeq: (j['lastSeq'] as num?)?.toInt() ?? 0,
        lastSyncAt: j['lastSyncAt'] == null ? null : DateTime.parse(j['lastSyncAt'] as String).toUtc(),
        createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
        isCurrent: j['isCurrent'] as bool? ?? false,
      );
}

/// `/api/v1/devices`. Throws [ApiError].
abstract interface class DevicesApi {
  /// Active (not removed) phones, oldest first.
  Future<List<RemoteDevice>> list();

  /// Owner only: removes a lost phone (it can't sync or sign in again). Idempotent.
  Future<void> remove(String id);
}

class DioDevicesApi implements DevicesApi {
  DioDevicesApi(this.dio);

  /// Authenticated dio.
  final Dio dio;

  ApiError _error(DioException e) => e.error is ApiError ? e.error! as ApiError : ApiError.fromDio(e);

  @override
  Future<List<RemoteDevice>> list() async {
    try {
      final r = await dio.get<dynamic>('/api/v1/devices');
      return [for (final d in r.data as List) RemoteDevice.fromJson((d as Map).cast<String, dynamic>())];
    } on DioException catch (e) {
      throw _error(e);
    }
  }

  @override
  Future<void> remove(String id) async {
    try {
      await dio.delete<dynamic>('/api/v1/devices/$id');
    } on DioException catch (e) {
      throw _error(e);
    }
  }
}

final devicesApiProvider = Provider<DevicesApi>((ref) => DioDevicesApi(ref.watch(apiDioProvider)));

/// The shop's phones (refetched when the screen opens or after a removal).
final remoteDevicesProvider = FutureProvider.autoDispose<List<RemoteDevice>>((ref) => ref.watch(devicesApiProvider).list());
