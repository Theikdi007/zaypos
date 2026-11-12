import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/devices/data/devices_api.dart';

import 'drift_helpers.dart';

/// STEP 4 against a running dev backend (skipped otherwise). The test asks
/// for its own OTPs and reads them from the backend's console log:
///   ZAYPOS_LIVE_API=http://127.0.0.1:5076 ZAYPOS_LIVE_LOG=/path/to/backend-output.log \
///   flutter test test/live_step4_test.dart
void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final log = env['ZAYPOS_LIVE_LOG'];
  final skip = base == null || log == null ? 'set ZAYPOS_LIVE_API and ZAYPOS_LIVE_LOG' : null;

  Iterable<RegExpMatch> codes(String phone) => RegExp('DEV SMS to ${RegExp.escape(phone)}: ZayPOS code: (\\d{6})')
      .allMatches(File(log!).readAsStringSync());
  int codeCount(String phone) => codes(phone).length;

  /// The newest "DEV SMS to <phone>: ZayPOS code: 123456", waiting until more
  /// than [after] codes were sent to that phone.
  Future<String> otpFor(String phone, {int after = 0}) async {
    for (var i = 0; i < 50; i++) {
      final all = codes(phone).toList();
      if (all.length > after) return all.last.group(1)!;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('no new OTP for $phone in $log');
  }

  test('bundled /sync/limits equals the server; presets import; devices remove; PIN reset', () async {
    final dbs = <AppDatabase>[];
    final apps = <ProviderContainer>[];
    addTearDown(() async {
      for (final c in apps) {
        c.dispose();
      }
      for (final d in dbs) {
        await d.close();
      }
    });
    Future<ProviderContainer> phoneApp() async {
      final db = memoryDb();
      dbs.add(db);
      final store = MemorySecureStore();
      final c = ProviderContainer(overrides: [
        ...driftOverrides(db, await bootstrap(db, store), store),
        apiBaseUrlProvider.overrideWithValue(base!),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 10, useIsolate: false)),
        initialLimitsProvider.overrideWithValue(SyncLimitsData.parse(File(bundledLimitsAsset).readAsStringSync())),
      ]);
      apps.add(c);
      return c;
    }

    Future<void> sync(ProviderContainer c) async {
      final e = c.read(syncEngineProvider);
      await e.syncNow(manual: true);
      expect(e.snapshot.lastError, isNull, reason: 'sync: ${e.snapshot.lastError}');
    }

    // ---- the bundled rules are the server's rules
    final server = (await Dio().get<String>('$base/api/v1/sync/limits', options: Options(responseType: ResponseType.plain))).data!;
    final bundled = SyncLimitsData.parse(File(bundledLimitsAsset).readAsStringSync());
    final live = SyncLimitsData.parse(server);
    expect(live.text.keys.toSet(), bundled.text.keys.toSet());
    for (final k in live.text.keys) {
      expect((live.text[k]!.maxLength, live.text[k]!.nonAscii), (bundled.text[k]!.maxLength, bundled.text[k]!.nonAscii), reason: k);
    }

    // ---- register a grocery shop with the preset catalog
    final phone = '+95979${Random().nextInt(900) + 100}${Random().nextInt(9000) + 1000}';
    final a = await phoneApp();
    final ctlA = a.read(authControllerProvider.notifier);
    await ctlA.requestOtp(phone, OtpPurpose.register);
    await ctlA.register(
        rawPhone: phone, otp: await otpFor(phone), shopName: 'Live step 4', templateId: 'grocery', pin: '135790',
        importPresets: true);
    expect(a.read(authControllerProvider).notice, isNull, reason: 'presets downloaded');
    final imported = await dbs[0].select(dbs[0].products).get();
    expect(imported, isNotEmpty);
    await sync(a); // first download, then the preset unit goes up
    expect(await dbs[0].select(dbs[0].outbox).get(), isEmpty, reason: 'the server accepted the preset unit');

    // ---- phone B sees the presets; A lists both phones and removes B
    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(phone, '135790');
    await sync(b);
    expect((await dbs[1].select(dbs[1].products).get()).length, imported.length);

    final listed = await a.read(devicesApiProvider).list();
    expect(listed.map((d) => (d.code, d.isCurrent)), [('A', true), ('B', false)]);
    await a.read(devicesApiProvider).remove(listed.last.id);
    expect((await a.read(devicesApiProvider).list()).map((d) => d.code), ['A']);

    await b.read(syncEngineProvider).syncNow(manual: true); // B is refused …
    expect(b.read(authControllerProvider).status, AuthStatus.signedOut, reason: '… and signed out (device_revoked)');
    expect(b.read(authControllerProvider).notice, contains(apiErrorMessage('device_revoked')));

    // ---- forgotten PIN on A: SMS code → new PIN → signed in again
    final codesBefore = codeCount(phone);
    await ctlA.requestOtp(phone, OtpPurpose.reset);
    await ctlA.resetPin(rawPhone: phone, otp: await otpFor(phone, after: codesBefore), newPin: '246810');
    expect(a.read(authControllerProvider).status, AuthStatus.unlocked);
    await sync(a); // the new session works
    await expectLater(
      a.read(authApiProvider).login(phone: phone, pin: '135790', deviceId: 'x'),
      throwsA(anything),
      reason: 'the old PIN no longer works',
    );
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}

