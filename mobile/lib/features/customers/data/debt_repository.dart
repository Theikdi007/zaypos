import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/debt_entry.dart';

/// Append-only debt ledger.
abstract interface class DebtRepository {
  /// Live entries, all customers, newest first.
  Stream<List<DebtEntry>> watchAll();
  Future<void> add(DebtEntry entry);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final debtRepositoryProvider = Provider<DebtRepository>(
  (_) => throw UnimplementedError('debtRepositoryProvider must be overridden'),
);
