import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../features/auth/application/auth_failure.dart';
import '../api/api_error.dart';

/// Crash reports (Firebase Crashlytics), release builds only.
///
/// PRIVACY RULE: an error's MESSAGE never leaves the phone. Messages can carry phone numbers, customer
/// and product names, amounts, emails or tokens (a server detail like "Barcode … is also used by:
/// Coke A.", a FormatException quoting a pulled row, a widget description in a FlutterError). A report
/// holds only [crashReason] (the error's type, plus the stable code of our own coded errors) and the
/// stack trace (code locations only). No user id, no custom keys, no logs. Android's own crash reports
/// (Java/Kotlin, plugins) are collected by the SDK as they are.
///
/// test/crash_reporting_test.dart checks the rule.

/// What a report says about [error]: its type, never its message.
String crashReason(Object error) => switch (error) {
      ApiError(:final status, :final code) => 'ApiError($status, ${_safeCode(code)})',
      AuthFailure(:final code) => 'AuthFailure(${_safeCode(code)})',
      _ => error.runtimeType.toString(),
    };

/// Our own codes are short snake_case ("invalid_credentials"); anything else (e.g. a ProblemDetails
/// title used as a code) is not sent.
String _safeCode(String code) => RegExp(r'^[a-z][a-z0-9_]{0,40}$').hasMatch(code) ? code : 'other';

/// The error as Crashlytics sees it: [toString] is [crashReason] only.
@visibleForTesting
class RedactedError implements Exception {
  RedactedError(Object error) : reason = crashReason(error);
  final String reason;

  @override
  String toString() => reason;
}

/// Sends one error (no-op until [startCrashReporting] has run, and in debug / profile builds).
Future<void> reportError(Object error, StackTrace? stack, {bool fatal = false}) async {
  if (!_started) return;
  try {
    await FirebaseCrashlytics.instance.recordError(
      RedactedError(error),
      stack,
      fatal: fatal,
      printDetails: false,
      // `reason` and `information` stay empty: they would be sent as written.
    );
  } catch (_) {
    // Crash reporting must never crash the app.
  }
}

var _started = false;

/// Starts Crashlytics on a release build when this build has a Firebase config (Android:
/// google-services.json at build time). Without one (iOS today, a dev build) it does nothing.
Future<void> startCrashReporting({bool release = kReleaseMode}) async {
  if (!release || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  } catch (e) {
    debugPrint('Crash reporting off: ${e.runtimeType}');
    return;
  }
  _started = true;

  // Flutter framework errors (layout, build, …): shown locally as before, sent redacted.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    unawaited(reportError(details.exception, details.stack));
  };
  // Uncaught errors outside Flutter callbacks (async code, platform channels).
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reportError(error, stack, fatal: true));
    return true;
  };
}
