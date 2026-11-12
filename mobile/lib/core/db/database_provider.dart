import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// The open local database (bound in main.dart).
final appDatabaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);
