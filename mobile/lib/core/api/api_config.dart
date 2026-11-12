import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `--dart-define=API_BASE_URL=http://10.0.2.2:5076` (docs/mobile/phase3-sync.md §8).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5076');

final apiBaseUrlProvider = Provider<String>((_) => apiBaseUrl);

/// True in release builds. A provider so tests can pretend to be a release build.
final isReleaseBuildProvider = Provider<bool>((_) => kReleaseMode);

/// Wall clock (UTC). Overridden in tests (token expiry, PIN lockout).
final clockProvider = Provider<DateTime Function()>((_) => () => DateTime.now().toUtc());
