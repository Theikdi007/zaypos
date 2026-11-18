// QA round 17: I/O for tests that run on a REAL iPhone without a driver connection (flutter drive cannot find the Dart
// VM service over Wi-Fi), and the same tests on the Android emulator through run_qa_android.sh.
//
// With QA_HOST (http://<Mac LAN IP>:8765, served by r17_host.py):
//   notes   → POST /note?run=<QA_RUN>   (also printed)
//   shots   → the app's own frame (render view layer) as PNG → POST /shot?name=
//   OTP     → GET /otp?phone=
// Without QA_HOST: the qa_harness.dart handshakes (shot / otpFor / note) used by run_qa.sh and run_qa_android.sh.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_harness.dart' as h;

const qaHost = String.fromEnvironment('QA_HOST');
bool get onHost => qaHost.isNotEmpty;

/// The evidence log name (QA_RUN, or the run name the host gave with the step).
String runName = h.qaRun;

/// Host action: through r17_host.py (driverless runs) or the flutter-drive runner (run_qa*.sh).
Future<void> hcmd(WidgetTester tester, String cmd) async {
  if (!onHost) return h.hostCmd(tester, cmd);
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final r = await (await c.getUrl(Uri.parse('$qaHost/cmd?c=$cmd'))).close();
    await r.drain<void>();
    c.close();
    rnote('host cmd $cmd → HTTP ${r.statusCode}');
  } catch (e) {
    rnote('host cmd $cmd failed: $e');
  }
}

Future<void> _chain = Future.value();

Future<void> _post(String path, List<int> body) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final rq = await c.postUrl(Uri.parse('$qaHost$path'));
    rq.contentLength = body.length;
    rq.add(body);
    await (await rq.close()).drain<void>();
    c.close();
  } catch (e) {
    // ignore: avoid_print
    print('QA_NOTE:host post $path failed: $e');
  }
}

/// A result line for the evidence log.
void rnote(String s) {
  h.note(s);
  if (onHost) {
    final line = 'QA_NOTE:${DateTime.now().toIso8601String().substring(11, 19)} $s';
    _chain = _chain.then((_) => _post('/note?run=${Uri.encodeQueryComponent(runName)}', utf8.encode(line)));
  }
}

Future<void> flushNotes() => _chain;

/// Screenshot: the real screen (host runner) on Android / simulator, the app's own frame on the real iPhone.
Future<void> snap(WidgetTester tester, String name) async {
  if (!onHost) return h.shot(tester, name);
  await h.settle(tester);
  await tester.pump(const Duration(milliseconds: 300));
  try {
    final view = RendererBinding.instance.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = view.layer! as OffsetLayer;
    final size = view.size;
    final dpr = view.flutterView.devicePixelRatio;
    // The root layer already scales by the device pixel ratio: capture the physical-size rect at ratio 1.
    final img = await layer.toImage(Offset.zero & (size * dpr), pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    await _chain;
    await _post('/shot?name=${Uri.encodeQueryComponent(name)}', png!.buffer.asUint8List());
    rnote('screenshot $name.png');
  } catch (e) {
    rnote('screenshot $name failed: $e');
  }
}

Future<int> otpCountR(String e164) async => onHost ? (await _codes(e164)).length : h.otpCount(e164);

Future<List<String>> _codes(String e164) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final r = await (await c.getUrl(Uri.parse('$qaHost/otp?phone=${Uri.encodeQueryComponent(e164)}'))).close();
  final body = await r.transform(utf8.decoder).join();
  c.close();
  return body.split('\n').where((l) => l.trim().length == 6).toList();
}

Future<String> otpForR(WidgetTester tester, String e164, {required int after}) async {
  if (!onHost) return h.otpFor(tester, e164, after: after);
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    final all = await _codes(e164);
    if (all.length > after) return all.last;
    await h.wait(tester, const Duration(milliseconds: 500));
  }
  fail('no new OTP for $e164 from the host');
}

/// Collects failed checks; asserted at the end so one run reports every finding.
class Checks {
  final failures = <String>[];
  void that(bool ok, String what, [Object? actual]) {
    rnote('${ok ? 'CHECK OK  ' : 'CHECK FAIL'} $what${actual == null ? '' : ' (actual: $actual)'}');
    if (!ok) failures.add('$what${actual == null ? '' : ' (actual: $actual)'}');
  }

  Future<void> finish(String step) async {
    rnote('QA_RESULT $step: ${failures.isEmpty ? 'PASS' : 'FAIL'} (${failures.length} failed checks)');
    for (final f in failures) {
      rnote('  FAILED: $f');
    }
    rnote('QA_DONE $step');
    await flushNotes();
  }
}

/// Types into [f]. Uses the test text input like qa_harness.type; on the real iPhone (profile build, no driver) the
/// test text input does not reach the field, so the text is then set on the controller and onChanged is called
/// (what the keyboard would do; input formatters are skipped there, which is noted).
Future<void> typeR(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f.first);
  await tester.enterText(f.first, text);
  await h.settle(tester);
  final w = tester.widget<EditableText>(f.first);
  if (w.controller.text != text && w.controller.text.replaceAll(' ', '') != text.replaceAll(' ', '')) {
    w.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    w.onChanged?.call(text);
    await h.settle(tester);
    rnote('typeR: test text input did not reach the field; set "$text" on the controller');
  }
}
