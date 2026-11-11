/// Quantities are stored as `int` milli-units: 1 unit = 1000, 2.5 ft = 2500.
/// No floating point is used for storage, parsing or display.
abstract final class Qty {
  static const scale = 1000;

  /// Whole units -> milli-units (3 -> 3000).
  static int units(int n) => n * scale;

  /// 2500 -> "2.5", 3000 -> "3", 750 -> "0.75", -1500 -> "-1.5".
  static String format(int milli) {
    final neg = milli < 0;
    final abs = milli.abs();
    final whole = abs ~/ scale;
    var frac = (abs % scale).toString().padLeft(3, '0');
    while (frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    final s = frac.isEmpty ? '$whole' : '$whole.$frac';
    return neg ? '-$s' : s;
  }

  /// Parses user input to milli-units. Returns null when invalid.
  /// When [decimal] is false only whole numbers are accepted
  /// (TenantFeatures.decimalQty off). At most 3 decimal places.
  static int? parse(String input, {required bool decimal}) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\.(\d{0,3}))?$').firstMatch(s);
    if (m == null) return null;
    final frac = m.group(2);
    if (frac != null && !decimal) return null;
    final whole = int.parse(m.group(1)!);
    final f = (frac ?? '').padRight(3, '0');
    return whole * scale + int.parse(f);
  }

  /// Money for a quantity: price (kyats per unit) × qty, rounded half away
  /// from zero to whole kyats (negative amounts, e.g. below-cost profit,
  /// round symmetrically).
  static int lineTotal(int priceKyats, int qtyMilli) {
    final p = priceKyats * qtyMilli;
    return p >= 0 ? (p + scale ~/ 2) ~/ scale : -((-p + scale ~/ 2) ~/ scale);
  }
}
