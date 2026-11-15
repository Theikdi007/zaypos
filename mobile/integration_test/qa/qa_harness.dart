// QA round 12b — shared harness for the iOS-simulator checks (integration_test).
//
// The app is started exactly like lib/main.dart (on-disk Drift DB "zaypos", the real Keychain store, the real API at
// API_BASE_URL). Only the camera scanner and the photo picker can be swapped: they need a real camera / photo library,
// so the "scanned" text and the "picked" bytes are injected (owner's rule for round 12b).
//
// The test talks to the host runner (integration_test/qa/run_qa.sh) through printed lines:
//   QA_SHOT:<name>   → the runner saves `xcrun simctl io <device> screenshot` as docs/qa/evidence/round-12b/<name>.png
//   QA_CMD:<command> → the runner does a host action (api_stop, api_start, kill_app, font_xxxl, font_default …)
// and then writes an ack file into QA_DIR, which the test waits for. The simulator app can read host paths.
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zaypos_app/app/drift_overrides.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/widgets/common.dart';
import 'package:zaypos_app/core/sync/sync_limits.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/main.dart';

const qaDir = String.fromEnvironment('QA_DIR');
const qaApiLog = String.fromEnvironment('QA_API_LOG');
const qaRun = String.fromEnvironment('QA_RUN', defaultValue: 'run');

IntegrationTestWidgetsFlutterBinding qaBinding() => IntegrationTestWidgetsFlutterBinding.ensureInitialized();

class QaApp {
  QaApp(this.container, this.db);
  final ProviderContainer container;
  final AppDatabase db;
  GoRouterLike get router => GoRouterLike(container);
}

/// Small wrapper so tests can navigate the real router.
class GoRouterLike {
  GoRouterLike(this.c);
  final ProviderContainer c;
  void go(String location) => c.read(appRouterProvider).go(location);
  void push(String location) => c.read(appRouterProvider).push(location);
  String get location => c.read(appRouterProvider).state.matchedLocation;
}

/// Starts the app like main.dart, with optional extra overrides (scanner, photo picker).
Future<QaApp> launchApp(WidgetTester tester, {List<Override> overrides = const []}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final db = AppDatabase(driftDatabase(name: 'zaypos'));
  const store = FlutterSecureStore();
  final boot = await bootstrap(db, store);
  final limits = await loadLimits(db);
  final c = ProviderContainer(overrides: [
    ...driftOverrides(db, boot, store),
    initialLimitsProvider.overrideWithValue(limits),
    ...overrides,
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
  await settle(tester);
  return QaApp(c, db);
}

/// pumpAndSettle that tolerates endless animations (spinners, the OTP timer): pumps for at most [max].
Future<void> settle(WidgetTester tester, {Duration max = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(max);
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
}

/// Real wall-clock wait while frames keep rendering.
Future<void> wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits until [finder] finds something (real time), or fails with [why].
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20), String? why}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'TIMEOUT_${DateTime.now().millisecondsSinceEpoch}');
      fail('timed out waiting for $finder${why == null ? '' : ' ($why)'}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

int _seq = 0;

Future<void> _handshake(WidgetTester tester, String line, String ackName, {Duration timeout = const Duration(seconds: 60)}) async {
  final ack = File('$qaDir/ack_$ackName');
  if (ack.existsSync()) ack.deleteSync();
  // ignore: avoid_print
  print(line);
  final end = DateTime.now().add(timeout);
  while (!ack.existsSync()) {
    if (DateTime.now().isAfter(end)) fail('host did not ack "$line" (is run_qa.sh driving this test?)');
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Screenshot of the whole simulator screen, taken by the host (xcrun simctl io … screenshot).
Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 300));
  await _handshake(tester, 'QA_SHOT:$name', 'shot_$name');
}

/// Host action (see run_qa.sh).
Future<void> hostCmd(WidgetTester tester, String cmd, {Duration timeout = const Duration(seconds: 120)}) async {
  final id = '${_seq++}_$cmd';
  await _handshake(tester, 'QA_CMD:$cmd:$id', 'cmd_$id', timeout: timeout);
}

/// Reads a dev OTP for [e164] from the API console log (the "DEV SMS to …" line), newer than [after] codes.
int otpCount(String e164) => _codes(e164).length;
List<String> _codes(String e164) => RegExp('DEV SMS to ${RegExp.escape(e164)}: ZayPOS code: (\\d{6})')
    .allMatches(File(qaApiLog).readAsStringSync())
    .map((m) => m.group(1)!)
    .toList();
Future<String> otpFor(WidgetTester tester, String e164, {required int after}) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    final all = _codes(e164);
    if (all.length > after) return all.last;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('no new OTP for $e164 in $qaApiLog');
}

/// The EditableText of the AppInput whose semanticLabel is [label].
Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is AppInput && w.semanticLabel == label), matching: find.byType(EditableText));

/// Types into [f] like a keyboard would (input formatters apply).
Future<void> type(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f.first);
  await tester.enterText(f.first, text);
  await settle(tester);
}

/// The text a field shows now.
String fieldText(WidgetTester tester, Finder f) => tester.widget<EditableText>(f.first).controller.text;

Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  await tester.ensureVisible(f);
  await settle(tester);
  await tester.tap(f);
  await settle(tester);
}

/// Logs a line that the runner keeps in the evidence log (QA_NOTE: …).
void note(String s) {
  // ignore: avoid_print
  print('QA_NOTE:$s');
}

/// Unlocks with [pin] on the PIN keypad if the app opened locked; waits until signed in.
Future<void> unlockIfLocked(WidgetTester tester, QaApp app, {String pin = '111111'}) async {
  if (find.text('PIN နံပါတ် ထည့်ပါ').evaluate().isEmpty) return;
  for (final d in pin.split('')) {
    await tester.ensureVisible(find.text(d).last);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(d).last);
    await tester.pump(const Duration(milliseconds: 120));
  }
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (find.text('PIN နံပါတ် ထည့်ပါ').evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) fail('still locked after PIN');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await settle(tester);
}

/// Signs in on the Login screen (typing [localPhone] and [pin]) if the app is signed out.
Future<void> signInIfSignedOut(WidgetTester tester, QaApp app, String localPhone, {String pin = '111111'}) async {
  if (find.text('ဝင်မယ်').evaluate().isEmpty) return;
  await type(tester, field('ဖုန်းနံပါတ်'), localPhone);
  await type(tester, field('PIN နံပါတ်'), pin);
  await tapText(tester, 'ဝင်မယ်');
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (find.text('ဝင်မယ်').evaluate().isNotEmpty || find.text('ဝင်နေသည်…').evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'signin_FAILED');
      fail('sign-in did not finish');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await wait(tester, const Duration(seconds: 5));
}

// ---------------------------------------------------------------- two-phone coordination (shared host folder)
const qaFlags = String.fromEnvironment('QA_FLAGS');

void raiseFlag(String name, [String value = '']) {
  File('$qaFlags/flag_$name').writeAsStringSync(value);
  note('flag raised: $name $value');
}

Future<String> awaitFlag(WidgetTester tester, String name, {Duration timeout = const Duration(minutes: 15)}) async {
  final f = File('$qaFlags/flag_$name');
  final end = DateTime.now().add(timeout);
  while (!f.existsSync()) {
    if (DateTime.now().isAfter(end)) fail('flag $name never came');
    await tester.pump(const Duration(milliseconds: 300));
  }
  note('flag seen: $name');
  return f.readAsStringSync();
}

/// Settings → "ယခု sync လုပ်မယ်", then waits until the button is idle again.
Future<void> syncNowViaUi(WidgetTester tester, QaApp app) async {
  app.router.go('/settings/features');
  await settle(tester);
  final btn = find.text('ယခု sync လုပ်မယ်');
  for (var i = 0; i < 15 && btn.evaluate().isEmpty; i++) {
    if (find.text('sync လုပ်နေသည်…').evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300)); // a sync is already running
      continue;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await settle(tester);
  }
  await waitFor(tester, btn, why: 'Settings sync section');
  await tapText(tester, 'ယခု sync လုပ်မယ်');
  await wait(tester, const Duration(milliseconds: 500));
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (find.text('sync လုပ်နေသည်…').evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await wait(tester, const Duration(seconds: 1));
}
