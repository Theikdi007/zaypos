import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/domain/customer.dart';

import 'drift_helpers.dart';
import 'fake_auth_api.dart';

void main() {
  late AppDatabase db;
  late MemorySecureStore store;
  late FakeAuthApi api;
  late DateTime now;
  final containers = <ProviderContainer>[];

  setUp(() {
    db = memoryDb();
    store = MemorySecureStore();
    api = FakeAuthApi();
    now = DateTime.utc(2026, 11, 12, 9);
  });
  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    await db.close();
  });

  /// The app as launched: bootstrap, then the Drift composition root.
  Future<ProviderContainer> launch({bool release = false}) async {
    final boot = await bootstrap(db, store);
    final c = ProviderContainer(overrides: [
      ...driftOverrides(db, boot, store),
      authApiProvider.overrideWithValue(api),
      pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
      clockProvider.overrideWithValue(() => now),
      isReleaseBuildProvider.overrideWithValue(release),
    ]);
    containers.add(c);
    return c;
  }

  AuthController auth(ProviderContainer c) => c.read(authControllerProvider.notifier);
  AuthStatus status(ProviderContainer c) => c.read(authControllerProvider).status;

  Future<void> addCustomerUnit(ProviderContainer c) async {
    final t = nowUtc();
    await c.read(customerServiceProvider).create(
          Customer(id: newId(), tenantId: c.read(tenantIdProvider), name: 'x', phone: '', createdAt: t, updatedAt: t),
        );
  }

  Future<int> rows(TableInfo<Table, Object?> t) async => (await db.select(t).get()).length;

  group('sign-in and local data', () {
    test('first login on a fresh install: session stored, this device row from the server, unlocked', () async {
      final c = await launch();
      expect(status(c), AuthStatus.signedOut);

      await auth(c).login('09 7123 4567', '123456');

      expect(status(c), AuthStatus.unlocked);
      expect(api.calls, ['login:+95971234567']);
      final s = c.read(sessionProvider);
      expect((s.tenantId, s.shopName, s.templateId, s.phone), (api.tenantId, 'ရွှေဝါ', 'pharmacy', '+95971234567'));
      final device = await db.select(db.devices).getSingle();
      expect((device.id, device.code, device.lastSeq), (c.read(deviceIdProvider), 'B', 7));
      expect(await LocalData(db).owner(), isA<LocalOwner>().having((o) => o.tenantId, 'tenant', api.tenantId));
      expect(store.values[SecureKeys.refreshToken], startsWith('refresh-'));
      expect(store.values[SecureKeys.pinHash], startsWith('pbkdf2-sha256\$'));
      expect(store.values.values, isNot(contains('123456')), reason: 'the PIN itself is never stored');
    });

    test('another shop while the outbox has units: refused BEFORE any network call, nothing changes', () async {
      final c = await launch();
      await auth(c).login('0971234567', '123456');
      await addCustomerUnit(c);
      await auth(c).signOut();

      await expectLater(
        auth(c).login('0979999999', '654321'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', 'outbox_not_empty')
            .having((e) => e.message, 'message', contains('၁ ခု'))),
      );
      await expectLater(auth(c).requestOtp('0979999999', OtpPurpose.register), throwsA(isA<AuthFailure>()));
      expect(api.calls, ['login:+95971234567'], reason: 'no login / otp for the other shop was sent');
      expect(await rows(db.customers), 1);
      expect(await outbox(db), hasLength(1));
      expect(status(c), AuthStatus.signedOut);
    });

    test('another shop with an empty outbox: every local table except the outbox is wiped', () async {
      final (seeded, _) = await driftContainer(db); // sample data owned by another shop
      seeded.dispose();
      expect(await rows(db.sales), greaterThan(500));
      final c = await launch();

      await auth(c).login('0979999999', '654321');

      for (final t in db.allTables) {
        final n = await rows(t);
        if (t.actualTableName == 'tenants' || t.actualTableName == 'devices') {
          expect(n, 1, reason: '${t.actualTableName}: only the new shop / this device');
        } else if (t.actualTableName == 'syncState') {
          final keys = (await db.select(db.syncState).get()).map((r) => r.key).toSet();
          expect(keys, {
            LocalStateKeys.installDeviceId,
            LocalStateKeys.ownerTenantId,
            LocalStateKeys.ownerPhone,
            LocalStateKeys.ownerDemo,
          });
        } else {
          expect(n, 0, reason: t.actualTableName);
        }
      }
      expect((await db.select(db.tenants).getSingle()).id, api.tenantId);
    });

    test('the same shop signing in again keeps the data and the outbox (lastSeq never moves back)', () async {
      final c = await launch();
      await auth(c).login('0971234567', '123456');
      await addCustomerUnit(c);
      await (db.update(db.devices)).write(const DevicesCompanion(lastSeq: Value(40)));
      await auth(c).signOut();

      await auth(c).login('09 7123 4567', '123456');

      expect(status(c), AuthStatus.unlocked);
      expect(await rows(db.customers), 1);
      expect(await outbox(db), hasLength(1));
      expect((await db.select(db.devices).getSingle()).lastSeq, 40, reason: 'server said 7, local 40 wins');
    });

    test('device_conflict when replacing local data: retried once with a new install id', () async {
      final c = await launch();
      final oldId = c.read(deviceIdProvider);
      api.nextError = const ApiError(409, 'device_conflict');

      await auth(c).login('0971234567', '123456');

      expect(api.deviceIds, hasLength(2));
      expect(api.deviceIds.first, oldId);
      final newDeviceId = c.read(deviceIdProvider);
      expect(newDeviceId, isNot(oldId));
      expect(api.deviceIds.last, newDeviceId);
      expect(store.values[SecureKeys.deviceId], newDeviceId);
      expect(await db.readState(LocalStateKeys.installDeviceId), newDeviceId);
    });

    test('register: guard, then /auth/register with the template; server errors become Burmese failures', () async {
      final c = await launch();
      api.nextError = const ApiError(400, 'otp_invalid');
      await expectLater(
        auth(c).register(rawPhone: '0971234567', otp: '000000', shopName: 'ဆေးဆိုင်', templateId: 'pharmacy', pin: '111111'),
        throwsA(isA<AuthFailure>().having((e) => e.message, 'message', apiErrorMessage('otp_invalid'))),
      );
      await auth(c).register(rawPhone: '0971234567', otp: '123456', shopName: 'ဆေးဆိုင်', templateId: 'pharmacy', pin: '111111');
      expect(api.calls.last, 'register:+95971234567:123456:ဆေးဆိုင်:pharmacy');
      expect(status(c), AuthStatus.unlocked);
    });

    test('bad phone / PIN fail locally without a network call', () async {
      final c = await launch();
      await expectLater(auth(c).login('12345', '123456'), throwsA(isA<AuthFailure>()));
      await expectLater(auth(c).login('0971234567', '12'), throwsA(isA<AuthFailure>()));
      expect(api.calls, isEmpty);
    });
  });

  group('offline PIN unlock', () {
    Future<ProviderContainer> signedInThenRestart() async {
      final c = await launch();
      await auth(c).login('0971234567', '123456');
      return launch(); // app restart: opens locked
    }

    test('a restart opens locked; the right PIN unlocks with no network', () async {
      final c = await signedInThenRestart();
      expect(status(c), AuthStatus.locked);
      expect(c.read(sessionProvider).tenantId, api.tenantId);
      api.calls.clear();

      await auth(c).unlock('123456');

      expect(status(c), AuthStatus.unlocked);
      expect(api.calls, isEmpty);
    });

    test('5 wrong PINs lock for 15 minutes, across restarts; then the right PIN works again', () async {
      var c = await signedInThenRestart();
      for (var left = 4; left >= 1; left--) {
        await expectLater(
          auth(c).unlock('000000'),
          throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'pin_wrong').having((e) => e.message, 'm', contains(mmNumber(left)))),
        );
      }
      await expectLater(auth(c).unlock('000000'), throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'pin_locked')));

      c = await launch(); // killing the app does not reset the lockout
      now = now.add(const Duration(minutes: 14));
      await expectLater(
        auth(c).unlock('123456'),
        throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'pin_locked').having((e) => e.message, 'm', contains('၁ မိနစ်'))),
      );
      expect(status(c), AuthStatus.locked);

      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(await auth(c).lockRemaining(), isNull);
      await auth(c).unlock('123456');
      expect(status(c), AuthStatus.unlocked);

      // A success resets the counter.
      c = await launch();
      await expectLater(auth(c).unlock('000000'), throwsA(isA<AuthFailure>().having((e) => e.message, 'm', contains(mmNumber(4)))));
    });
  });

  group('session end', () {
    test('refresh refused (device_revoked): signed out, tokens gone, local data and outbox kept, warning shown', () async {
      final c = await launch();
      await auth(c).login('0971234567', '123456');
      await addCustomerUnit(c);

      await c.read(tokenRefresherProvider).onSessionEnded('device_revoked');

      final s = c.read(authControllerProvider);
      expect(s.status, AuthStatus.signedOut);
      expect(s.notice, allOf(contains(apiErrorMessage('device_revoked')), contains(AuthMessages.outboxKept(1))));
      expect(store.values.keys, [SecureKeys.deviceId], reason: 'only the install id survives sign-out');
      expect(await outbox(db), hasLength(1));
      expect(await rows(db.customers), 1);
    });
  });

  group('install', () {
    test('a fresh install (no marker in the database) wipes Keychain leftovers and makes a new device id', () async {
      store.values.addAll({SecureKeys.deviceId: 'old-device', SecureKeys.refreshToken: 'stale', SecureKeys.tenantId: 't'});
      final boot = await bootstrap(db, store);
      expect(boot.deviceId, isNot('old-device'));
      expect(boot.session, isNull);
      expect(store.values, {SecureKeys.deviceId: boot.deviceId});
      expect(await db.readState(LocalStateKeys.installDeviceId), boot.deviceId);

      expect((await bootstrap(db, store)).deviceId, boot.deviceId, reason: 'same install: same id');
    });

    test('a stored session whose shop does not own the local data is dropped', () async {
      final c = await launch();
      await auth(c).login('0971234567', '123456');
      await db.writeState(LocalStateKeys.ownerTenantId, 'someone-else');
      expect((await bootstrap(db, store)).session, isNull);
      expect(store.values.containsKey(SecureKeys.refreshToken), isFalse);
    });
  });

  group('sample data is impossible in release builds', () {
    test('seedSampleShop refuses (assert in debug, StateError at runtime) and writes nothing', () async {
      await expectLater(
        seedSampleShop(db, tenantId: 't', deviceId: 'd', releaseMode: true),
        throwsA(anyOf(isA<AssertionError>(), isA<StateError>())),
      );
      expect(await rows(db.products), 0);
      expect(await rows(db.sales), 0);
    });

    test('LocalData.openDemo throws in release mode', () async {
      await expectLater(LocalData(db).openDemo(deviceId: 'd', releaseMode: true), throwsStateError);
      expect(await LocalData(db).owner(), isNull);
    });

    test('the demo shop cannot be opened from a release build', () async {
      final c = await launch(release: true);
      await expectLater(auth(c).openDemo(), throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'demo_unavailable')));
      expect(await rows(db.products), 0);
      expect(status(c), AuthStatus.signedOut);
    });

    test('debug: the demo shop is seeded once, never pushed, and its unpushed units block a real sign-in', () async {
      final c = await launch();
      await auth(c).openDemo();
      expect(status(c), AuthStatus.unlocked);
      expect(c.read(sessionProvider).isDemo, isTrue);
      expect(await rows(db.sales), greaterThan(500));
      expect(await outbox(db), isEmpty);

      await addCustomerUnit(c);
      await auth(c).signOut();
      await auth(c).openDemo(); // re-opening keeps the demo data
      expect(await rows(db.customers), greaterThan(7));
      await auth(c).signOut();

      await expectLater(auth(c).login('0971234567', '123456'),
          throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'outbox_not_empty')));
      expect(api.calls, isEmpty);
    });
  });
}
