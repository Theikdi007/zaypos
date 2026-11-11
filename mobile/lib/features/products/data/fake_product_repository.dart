import '../../../app/fake_seed.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../domain/product.dart';
import 'product_repository.dart';

/// In-memory sample data (from the design). Replaced by API + Drift later.
class FakeProductRepository implements ProductRepository {
  FakeProductRepository({required this.tenantId}) {
    final t = nowUtc();
    Product p(String id, String name, int cost, int price, int stock, String cat, int tint, String initial) => Product(
          id: id,
          tenantId: tenantId,
          name: name,
          cost: cost,
          price: price,
          stockMilli: Qty.units(stock),
          category: cat,
          tint: tint,
          initial: initial,
          createdAt: t,
          updatedAt: t,
        );
    _items.addAll([
      p(SeedIds.water, 'ရေသန့် 1L', 450, 600, 48, 'အချိုရည်', AppColors.tintBlue.toARGB32(), 'ရ'),
      p(SeedIds.oil, 'စားသုံးဆီ 1L', 5600, 6200, 3, 'စားသောက်ကုန်', AppColors.tintAmber.toARGB32(), 'ဆီ'),
      p(SeedIds.rice, 'ဆန် ပေါ်ဆန်း (၁ ပြည်)', 6800, 7400, 20, 'စားသောက်ကုန်', AppColors.tintGrayMid.toARGB32(), 'ဆ'),
      p(SeedIds.soap, 'ဆပ်ပြာမှုန့် 500g', 2300, 2800, 2, 'အိမ်သုံး', AppColors.tintIndigo.toARGB32(), 'ပ'),
      p(SeedIds.eggs, 'ကြက်ဥ (၁၀ လုံး)', 4000, 4500, 15, 'စားသောက်ကုန်', AppColors.tintOrange.toARGB32(), 'ဥ'),
      p(SeedIds.coffee, 'ကော်ဖီမစ် (၁၀ ထုပ်)', 3000, 3500, 0, 'အချိုရည်', AppColors.tintYellow.toARGB32(), 'က'),
      p(SeedIds.noodles, 'ခေါက်ဆွဲခြောက်', 700, 900, 60, 'မုန့်', AppColors.tintPink.toARGB32(), 'ခ'),
    ]);
  }

  final String tenantId;
  final _items = <Product>[];
  final _variants = <ProductVariant>[];

  @override
  List<Product> list() => List.unmodifiable(_items.where((p) => !p.isDeleted));

  @override
  List<ProductVariant> variantsOf(String productId) =>
      List.unmodifiable(_variants.where((v) => v.productId == productId && v.deletedAt == null));

  @override
  void add(Product product, {List<ProductVariant> variants = const []}) {
    _items.insert(0, product);
    _variants.addAll(variants);
  }

  @override
  void adjustStock(String productId, int deltaMilli) {
    final i = _items.indexWhere((p) => p.id == productId);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(stockMilli: _items[i].stockMilli + deltaMilli, updatedAt: nowUtc());
  }
}
