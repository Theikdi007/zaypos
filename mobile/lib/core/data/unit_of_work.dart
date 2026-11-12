import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Server unit kinds (`POST /sync/push`, docs/backend/README.md §3.1). The
/// enum name is the wire value.
enum UnitKind { checkout, voidSale, payDebt, upsertProduct, upsertCustomer, setFeatures, stockAdjust, restock }

/// Runs a group of repository writes atomically: either every write in
/// [run]'s body is kept, or (if it throws) none are. The Drift
/// implementation also records the rows written as ONE outbox unit of
/// [kind], committed in the same transaction (docs/mobile/phase3-sync.md §4).
///
/// A nested [run] joins the outer unit (and its kind).
abstract interface class UnitOfWork {
  Future<T> run<T>(UnitKind kind, Future<T> Function() body);
}

/// Bound at the composition root (lib/app/drift_overrides.dart; tests use
/// lib/app/fake_overrides.dart).
final unitOfWorkProvider = Provider<UnitOfWork>(
  (_) => throw UnimplementedError('unitOfWorkProvider must be overridden'),
);
