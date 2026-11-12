import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/db/local_data.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/sync/sync_store.dart';
import '../../../core/utils/ids.dart';
import 'session_store.dart';

/// What the app knows at launch, before the first frame.
class BootState {
  const BootState({required this.deviceId, this.session, this.startUnlocked = false, this.initialSyncDone = false});

  /// This install's device id (UUID v7, generated once per install).
  final String deviceId;

  /// The local data already holds a full download of the session's shop (§5.4).
  final bool initialSyncDone;

  /// The stored session, if any (the app then opens on the PIN unlock).
  final StoredSession? session;

  /// TESTS ONLY: open already unlocked with [session].
  final bool startUnlocked;
}

/// Runs before `runApp`:
/// - a missing install marker in the (app-sandboxed) database means a fresh
///   install: secure-storage leftovers (the iOS Keychain survives uninstall)
///   are wiped and a new deviceId is generated — a reinstall is a new device;
/// - a stored session is kept only if the local data belongs to its shop.
Future<BootState> bootstrap(AppDatabase db, SecureStore store) async {
  final marker = await db.readState(LocalStateKeys.installDeviceId);
  var deviceId = await store.read(SecureKeys.deviceId);
  if (marker == null || deviceId == null || marker != deviceId) {
    await store.deleteAll();
    deviceId = newId();
    await store.write(SecureKeys.deviceId, deviceId);
    await db.writeState(LocalStateKeys.installDeviceId, deviceId);
  }

  final sessions = SessionStore(store);
  var session = await sessions.load();
  final owner = await LocalData(db).owner();
  if (session != null && (owner == null || owner.isDemo || owner.tenantId != session.tenantId)) {
    await sessions.clear();
    session = null;
  }
  return BootState(
    deviceId: deviceId,
    session: session,
    initialSyncDone: await db.readState(SyncStateKeys.initialSyncDone) == 'true',
  );
}

/// Bound in main.dart from [bootstrap]. Default (tests): a fresh install, signed out.
final bootStateProvider = Provider<BootState>((_) => BootState(deviceId: newId()));

/// This install's device id. Replaced only when the server says the id is
/// registered to another shop (`device_conflict`) and the local data is
/// being replaced anyway.
class DeviceIdNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(bootStateProvider).deviceId;

  Future<String> replace() async {
    final id = newId();
    await ref.read(secureStoreProvider).write(SecureKeys.deviceId, id);
    await ref.read(appDatabaseProvider).writeState(LocalStateKeys.installDeviceId, id);
    state = id;
    return id;
  }
}

final deviceIdProvider = NotifierProvider<DeviceIdNotifier, String>(DeviceIdNotifier.new);
