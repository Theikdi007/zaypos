import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a group of repository writes atomically: either every write in
/// [run]'s body is kept, or (if it throws) none are. Drift implementation:
/// `db.transaction(body)`.
abstract interface class UnitOfWork {
  Future<T> run<T>(Future<T> Function() body);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final unitOfWorkProvider = Provider<UnitOfWork>(
  (_) => throw UnimplementedError('unitOfWorkProvider must be overridden'),
);
