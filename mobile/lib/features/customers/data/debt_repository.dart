import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/debt_entry.dart';

/// Append-only debt ledger.
abstract interface class DebtRepository {
  /// Live entries, all customers, newest first.
  Stream<List<DebtEntry>> watchAll();

  /// Balance owed per customer id (kyats): SUM of live entries' effects
  /// (payment −amount, creditSale/adjustment +amount). Customers without
  /// entries are absent (= 0).
  Stream<Map<String, int>> watchBalances();
  Future<void> add(DebtEntry entry);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final debtRepositoryProvider = Provider<DebtRepository>(
  (_) => throw UnimplementedError('debtRepositoryProvider must be overridden'),
);
