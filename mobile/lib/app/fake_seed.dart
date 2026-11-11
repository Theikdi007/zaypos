import '../core/utils/ids.dart';

/// Stable ids for the design's sample data so the fake repositories can
/// reference each other (sale ↔ customer ↔ debt entry). Generated once per
/// app run as UUID v7.
abstract final class SeedIds {
  // Products
  static final water = newId();
  static final oil = newId();
  static final rice = newId();
  static final soap = newId();
  static final eggs = newId();
  static final coffee = newId();
  static final noodles = newId();

  // Customers
  static final thanHtun = newId();
  static final khinMa = newId();
  static final aungKyaw = newId();
  static final zawMin = newId();
  static final niNi = newId();
  static final myatNoe = newId();
  static final htet = newId();

  // Sales
  static final sale1032 = newId();
  static final sale1031 = newId();
  static final sale1030 = newId();
  static final sale1029 = newId();
  static final sale1028 = newId();
  static final sale1027 = newId();
}

/// Local "today at h:m", in UTC.
DateTime todayAt(int hour, int minute) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour, minute).toUtc();
}

/// Local "[days] ago at h:m", in UTC.
DateTime daysAgoAt(int days, int hour, int minute) {
  final n = DateTime.now().subtract(Duration(days: days));
  return DateTime(n.year, n.month, n.day, hour, minute).toUtc();
}
