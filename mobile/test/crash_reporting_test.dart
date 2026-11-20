// Crash reports never carry an error's message: no phone numbers, customer names, amounts, emails or
// tokens (lib/core/crash/crash_reporting.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/api/api_error.dart';
import 'package:zaypos_app/core/crash/crash_reporting.dart';
import 'package:zaypos_app/features/auth/application/auth_failure.dart';

void main() {
  const secrets = [
    '09790917041', '+959790917041', 'ဒေါ်ခင်မာ', 'Mg Aung', '96,600', '3100', 'shop@example.com',
    'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln', 'Coke A',
  ];

  void expectNoSecrets(String reason) {
    for (final s in secrets) {
      expect(reason, isNot(contains(s)), reason: 'sent "$reason"');
    }
  }

  test('errors with personal data in their message are reported by type only', () {
    final errors = <Object>[
      FormatException('customers.phone: 09790917041 (ဒေါ်ခင်မာ) owes 96,600 Ks'),
      StateError('token eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln for shop@example.com'),
      Exception('Mg Aung 3100 +959790917041'),
      ArgumentError.value('Coke A', 'name'),
      'a thrown string: Mg Aung',
    ];
    for (final e in errors) {
      final r = RedactedError(e);
      expectNoSecrets(r.reason);
      expectNoSecrets(r.toString());
    }
    expect(crashReason(const FormatException('x')), 'FormatException');
  });

  test('our coded errors keep only their status and stable code', () {
    expect(crashReason(const ApiError(409, 'duplicate_barcode', detail: 'Barcode 8850 is also used by: Coke A.')),
        'ApiError(409, duplicate_barcode)');
    expect(crashReason(const AuthFailure('pin_wrong', 'PIN မှားနေပါတယ်။ နောက်ထပ် ၄ ကြိမ်')), 'AuthFailure(pin_wrong)');
    // A code that isn't one of ours (a ProblemDetails title) is not sent either.
    expect(crashReason(const ApiError(400, 'Phone 09790917041 is taken')), 'ApiError(400, other)');
  });

  test('a Flutter error describing a widget with a customer name is sent without it', () {
    final details = FlutterErrorDetails(
      exception: FlutterError('A RenderFlex overflowed: Text("ဒေါ်ခင်မာ 96,600 Ks")'),
      stack: StackTrace.current,
    );
    expect(RedactedError(details.exception).reason, 'FlutterError');
  });

  test('reporting before start (tests, debug, iOS) is a no-op', () async {
    await reportError(Exception('x'), StackTrace.current);
    await startCrashReporting(release: false);
  });
}
