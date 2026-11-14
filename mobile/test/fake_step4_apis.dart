import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/features/devices/data/devices_api.dart';
import 'package:zaypos_app/features/products/data/preset_catalog_api.dart';

class FakePresetApi implements PresetCatalogApi {
  FakePresetApi(this.items);
  final List<PresetItem> items;
  ApiError? error;
  final fetched = <String>[];

  @override
  Future<List<PresetItem>> fetch(String templateId) async {
    fetched.add(templateId);
    if (error != null) throw error!;
    return items;
  }
}

class FakeDevicesApi implements DevicesApi {
  FakeDevicesApi(this.devices);
  final List<RemoteDevice> devices;
  final removed = <String>[];
  ApiError? listError;

  @override
  Future<List<RemoteDevice>> list() async {
    if (listError != null) throw listError!;
    return devices.where((d) => !removed.contains(d.id)).toList();
  }

  @override
  Future<void> remove(String id) async => removed.add(id);
}

RemoteDevice remoteDevice(String id, String code, {bool current = false, String? name}) => RemoteDevice(
      id: id,
      code: code,
      name: name,
      lastSeq: 12,
      lastSyncAt: DateTime.utc(2026, 11, 12, 8),
      createdAt: DateTime.utc(2026, 11, 1),
      isCurrent: current,
    );
