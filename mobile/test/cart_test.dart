import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/utils/qty.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/domain/product.dart';

Product _product(String id, int price) {
  final t = DateTime.utc(2026);
  return Product(
    id: id,
    tenantId: 't',
    name: id,
    cost: 0,
    price: price,
    stockMilli: 0,
    category: '',
    tint: 0,
    initial: '',
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  late ProviderContainer c;
  late CartNotifier cart;
  setUp(() {
    c = ProviderContainer();
    cart = c.read(cartProvider.notifier);
  });
  tearDown(() => c.dispose());

  test('starts empty', () {
    expect(c.read(cartProvider).isEmpty, isTrue);
    expect(c.read(cartProvider).total, 0);
  });

  test('adding the same product increments its quantity', () {
    final water = _product('water', 600);
    cart.addProduct(water);
    cart.addProduct(water);
    final s = c.read(cartProvider);
    expect(s.lines, hasLength(1));
    expect(s.qtyOf('water'), Qty.units(2));
    expect(s.total, 1200);
  });

  test('totals combine products and quick-sale lines', () {
    cart.addProduct(_product('water', 600));
    cart.addProduct(_product('rice', 7400));
    cart.addQuick(2500, '');
    final s = c.read(cartProvider);
    expect(s.total, 600 + 7400 + 2500);
    expect(s.countMilli, Qty.units(3));
    expect(s.quickLines.single.name, quickSaleName);
  });

  test('setQty never drops below one unit', () {
    cart.addProduct(_product('water', 600));
    cart.setQty('water', Qty.units(5));
    expect(c.read(cartProvider).total, 3000);
    cart.setQty('water', 0);
    expect(c.read(cartProvider).qtyOf('water'), Qty.units(1));
  });

  test('fractional quantity totals in whole kyats', () {
    cart.addProduct(_product('pipe', 1200));
    cart.setQty('pipe', 2500); // 2.5 ft
    expect(c.read(cartProvider).total, 3000);
  });

  test('drafts carry productId, qty and price', () {
    cart.addProduct(_product('water', 600));
    cart.addQuick(1000, 'ဆပ်ပြာ');
    final d = c.read(cartProvider).toDrafts();
    expect(d.first, (productId: 'water', name: 'water', qtyMilli: 1000, price: 600));
    expect(d.last.productId, isNull);
    expect(d.last.name, 'ဆပ်ပြာ');
  });

  test('clear empties the cart', () {
    cart.addQuick(500, '');
    cart.clear();
    expect(c.read(cartProvider).isEmpty, isTrue);
  });
}
