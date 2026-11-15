// QA round 12 — live: BUG-34 (205c5d7) sign-in paths against the REAL API and a scratch database. The app's own auth
// controller is used with the phone number written in Myanmar digits, with dots, with "+95 9 …" and with dashes. The test
// asks for its own OTPs and reads them from the API's console log:
//   ZAYPOS_LIVE_API=http://127.0.0.1:5077 ZAYPOS_LIVE_PHONE=+9597… ZAYPOS_LIVE_LOG=/path/to/api.log \
//   flutter test test/qa/live_qa_round12_test.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/api/api_config.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/local_data.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/sync/sync_providers.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/features/auth/application/auth_controller.dart';
import 'package:zaypos_app/features/auth/data/auth_api.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/auth/data/session.dart';
import 'package:zaypos_app/features/auth/domain/pin_hasher.dart';
import 'package:zaypos_app/features/products/application/product_service.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

import '../drift_helpers.dart';

void main() {
  final env = Platform.environment;
  final base = env['ZAYPOS_LIVE_API'];
  final phone = env['ZAYPOS_LIVE_PHONE'];
  final log = env['ZAYPOS_LIVE_LOG'];
  final skip = base == null || phone == null || log == null ? 'set ZAYPOS_LIVE_API/PHONE/LOG' : null;

  Iterable<RegExpMatch> codes(String p) =>
      RegExp('DEV SMS to ${RegExp.escape(p)}: ZayPOS code: (\\d{6})').allMatches(File(log!).readAsStringSync());
  Future<String> otpFor(String p, {required int after}) async {
    for (var i = 0; i < 50; i++) {
      final all = codes(p).toList();
      if (all.length > after) return all.last.group(1)!;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('no new OTP for $p in $log');
  }

  test('TC-AUTH-NEW-3 live r12: register with an OTP asked in Myanmar digits and the number typed with dots; phone B signs '
      'in with "+95 9 …"; phone A signs in again in Myanmar digits with an UNSENT unit (same shop → allowed, data kept); '
      'PIN reset asked with dashes and done in Myanmar digits; phone C signs in with the new PIN; one shop, ASCII E.164 '
      'everywhere', () async {
    final dbs = <AppDatabase>[];
    final containers = <ProviderContainer>[];
    addTearDown(() async {
      for (final c in containers) {
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
      ]);
      containers.add(c);
      return c;
    }

    AppDatabase dbOf(ProviderContainer c) => dbs[containers.indexOf(c)];
    Future<void> sync(ProviderContainer c) async {
      final e = c.read(syncEngineProvider);
      await e.syncNow(manual: true);
      expect(e.snapshot.lastError, isNull, reason: 'sync failed: ${e.snapshot.lastError}');
    }

    final p = phone!; // +9597xxxxxxxx
    final national = '0${p.substring(3)}'; // 097xxxxxxxx
    final mm = String.fromCharCodes(national.codeUnits.map((u) => 0x1040 + u - 0x30));
    final dotted = '${national.substring(0, 2)}.${national.substring(2, 5)}.${national.substring(5, 8)}.${national.substring(8)}';
    final spaced = '+95 ${p.substring(3, 4)} ${p.substring(4, 7)} ${p.substring(7, 10)} ${p.substring(10)}';
    final dashed = '959-${p.substring(4, 7)}-${p.substring(7, 10)}-${p.substring(10)}';
    // ignore: avoid_print
    print('r12 forms: mm=$mm dotted=$dotted spaced=$spaced dashed=$dashed');

    // ---- register: OTP asked in Myanmar digits, register typed with dots
    final a = await phoneApp();
    final ctlA = a.read(authControllerProvider.notifier);
    final before = codes(p).length;
    await ctlA.requestOtp(mm, OtpPurpose.register);
    await ctlA.register(rawPhone: dotted, otp: await otpFor(p, after: before), shopName: 'QA live r12', templateId: 'grocery',
        pin: '864200');
    await sync(a);
    final tid = a.read(tenantIdProvider);
    expect(await dbOf(a).readState(LocalStateKeys.ownerPhone), p, reason: 'stored as ASCII E.164');

    final t = nowUtc();
    final soap = Product(id: newId(), tenantId: tid, name: 'QA r12 soap', cost: 100, price: 150, category: 'x', tint: 0,
        initial: 'Q', createdAt: t, updatedAt: t);
    await a.read(productServiceProvider).create(soap);
    await sync(a);

    // ---- phone B: "+95 9 …"
    final b = await phoneApp();
    await b.read(authControllerProvider.notifier).login(spaced, '864200');
    await sync(b);
    expect(b.read(tenantIdProvider), tid);
    expect((await dbOf(b).select(dbOf(b).products).get()).map((x) => x.name), contains('QA r12 soap'));

    // ---- phone A again, Myanmar digits, with an UNSENT unit: same shop → allowed, nothing replaced
    final t2 = nowUtc();
    final unsent = Product(id: newId(), tenantId: tid, name: 'QA r12 unsent', cost: 100, price: 150, category: 'x', tint: 0,
        initial: 'Q', createdAt: t2, updatedAt: t2);
    await a.read(productServiceProvider).create(unsent);
    final pendingBefore = (await dbOf(a).select(dbOf(a).outbox).get()).length;
    await a.read(authControllerProvider.notifier).login(mm, '864200');
    final aNames = (await dbOf(a).select(dbOf(a).products).get()).map((x) => x.name).toSet();
    // ignore: avoid_print
    print('r12 A re-sign-in: pending before=$pendingBefore, products=$aNames');
    expect(pendingBefore, greaterThan(0));
    expect(aNames, containsAll(['QA r12 soap', 'QA r12 unsent']));
    await sync(a);
    await sync(b);
    expect((await dbOf(b).select(dbOf(b).products).get()).map((x) => x.name), contains('QA r12 unsent'));

    // ---- PIN reset: OTP asked with dashes, reset typed in Myanmar digits
    final n = codes(p).length;
    await ctlA.requestOtp(dashed, OtpPurpose.reset);
    await ctlA.resetPin(rawPhone: mm, otp: await otpFor(p, after: n), newPin: '531642');
    expect(a.read(tenantIdProvider), tid);
    expect((await dbOf(a).select(dbOf(a).products).get()).map((x) => x.name), containsAll(['QA r12 soap', 'QA r12 unsent']),
        reason: 'the reset signs A in again as the same shop; its data is kept');

    // ---- phone C with the new PIN (dotted); the old PIN is refused
    final c = await phoneApp();
    Object? oldPin;
    try {
      await c.read(authControllerProvider.notifier).login(dotted, '864200');
    } on AuthFailure catch (e) {
      oldPin = e.code;
    }
    expect(oldPin, isNotNull, reason: 'the old PIN no longer works');
    await c.read(authControllerProvider.notifier).login(dotted, '531642');
    await sync(c);
    expect(c.read(tenantIdProvider), tid);
    expect((await dbOf(c).select(dbOf(c).products).get()).map((x) => x.name), containsAll(['QA r12 soap', 'QA r12 unsent']));

    // ---- raw API: an OTP request in Myanmar digits for the registered number is the same number (409 for register)
    final res = await Dio(BaseOptions(baseUrl: base!, validateStatus: (_) => true))
        .post<Map<String, dynamic>>('/api/v1/auth/otp', data: {'phone': mm, 'purpose': 'register'});
    // ignore: avoid_print
    print('r12 raw OTP (register, Myanmar digits, registered number): ${res.statusCode} ${res.data?['code']}');
    expect((res.statusCode, res.data?['code']), (409, 'phone_registered'));
    expect(codes(p).length, n + 1, reason: 'two SMS in total for this number in this run after the register one');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
