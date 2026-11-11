import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/customer.dart';

abstract interface class CustomerRepository {
  /// Live (not soft-deleted) customers.
  List<Customer> list();
  void add(Customer customer);
}

/// Bound at the composition root (lib/app/fake_overrides.dart).
final customerRepositoryProvider = Provider<CustomerRepository>(
  (_) => throw UnimplementedError('customerRepositoryProvider must be overridden'),
);
