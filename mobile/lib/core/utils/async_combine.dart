import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Joins two async values: error if either failed, loading until both have
/// data, then [f] of both values.
AsyncValue<R> combineAsync<A, B, R>(AsyncValue<A> a, AsyncValue<B> b, R Function(A a, B b) f) {
  if (a.hasError) return AsyncError<R>(a.error!, a.stackTrace ?? StackTrace.empty);
  if (b.hasError) return AsyncError<R>(b.error!, b.stackTrace ?? StackTrace.empty);
  if (a.hasValue && b.hasValue) return AsyncData<R>(f(a.requireValue, b.requireValue));
  return AsyncLoading<R>();
}

/// Combined state of several values: error if any failed, loading until all
/// have data. Use `.requireValue` on each input once this has a value.
AsyncValue<void> allReady(List<AsyncValue<Object?>> values) {
  for (final v in values) {
    if (v.hasError) return AsyncError<void>(v.error!, v.stackTrace ?? StackTrace.empty);
  }
  return values.every((v) => v.hasValue) ? const AsyncData<void>(null) : const AsyncLoading<void>();
}
