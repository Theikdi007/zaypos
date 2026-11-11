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

/// Sample catalog row shared by the fake product and sales repositories.
class SeedProduct {
  const SeedProduct(this.id, this.name, this.cost, this.price, this.category, this.tint, this.initial, this.unit);
  final String id;
  final String name;
  final int cost;
  final int price;
  final String category;
  final int tint;
  final String initial;
  final String unit;
}

abstract final class SeedCatalog {
  static final items = <SeedProduct>[
    SeedProduct(SeedIds.water, 'ရေသန့် 1L', 450, 600, 'အချိုရည်', 0xFFDBEAFE, 'ရ', 'ဘူး'),
    SeedProduct(SeedIds.oil, 'စားသုံးဆီ 1L', 5600, 6200, 'စားသောက်ကုန်', 0xFFFEF3C7, 'ဆီ', 'ဗူး'),
    SeedProduct(SeedIds.rice, 'ဆန် ပေါ်ဆန်း (၁ ပြည်)', 6800, 7400, 'စားသောက်ကုန်', 0xFFE5E7EB, 'ဆ', 'ပြည်'),
    SeedProduct(SeedIds.soap, 'ဆပ်ပြာမှုန့် 500g', 2300, 2800, 'အိမ်သုံး', 0xFFE0E7FF, 'ပ', 'ထုပ်'),
    SeedProduct(SeedIds.eggs, 'ကြက်ဥ (၁၀ လုံး)', 4000, 4500, 'စားသောက်ကုန်', 0xFFFFEDD5, 'ဥ', 'ကတ်'),
    SeedProduct(SeedIds.coffee, 'ကော်ဖီမစ် (၁၀ ထုပ်)', 3000, 3500, 'အချိုရည်', 0xFFFDE68A, 'က', 'ထုပ်'),
    SeedProduct(SeedIds.noodles, 'ခေါက်ဆွဲခြောက်', 700, 900, 'မုန့်', 0xFFFCE7F3, 'ခ', 'ထုပ်'),
  ];

  static SeedProduct byId(String id) => items.firstWhere((p) => p.id == id);

  /// Non-catalog items sold on the design's sample receipts.
  static const salt = ('ဆား', 400, 500); // (name, cost, price)
  static const lighter = ('မီးခြစ်', 300, 400);
}
