import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/features/devices/data/device_providers.dart';
import 'package:zaypos_app/features/devices/data/fake_device_repository.dart';
import 'package:zaypos_app/features/devices/domain/device.dart';
import 'package:zaypos_app/features/sales/data/sales_providers.dart';
import 'package:zaypos_app/features/sales/domain/sale.dart';

import 'helpers.dart';

void main() {
  test('format: code + 4-digit sequence', () {
    expect(formatReceiptNo('A', 1033), 'A-1033');
    expect(formatReceiptNo('B', 7), 'B-0007');
    expect(formatReceiptNo('A', 12345), 'A-12345');
  });

  test('each device issues its own unique, increasing sequence', () {
    final a = FakeDeviceRepository(tenantId: 't', code: 'A', lastSeq: 0);
    final b = FakeDeviceRepository(tenantId: 't', code: 'B', lastSeq: 0);
    final issued = [
      for (var i = 0; i < 50; i++) ...[a.issueReceiptNo(), b.issueReceiptNo()],
    ];
    expect(issued.toSet(), hasLength(100)); // no collisions across devices
    expect(issued.take(4), ['A-0001', 'B-0001', 'A-0002', 'B-0002']);
    expect(a.current().lastSeq, 50);
    expect(b.current().nextReceiptNo, 'B-0051');
  });

  test('sales get consecutive numbers from the current device', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(deviceProvider).nextReceiptNo, 'A-1033');
    final sales = c.read(salesProvider.notifier);
    final line = (productId: null, name: 'x', qtyMilli: 1000, price: 100);
    final s1 = sales.create(method: PaymentMethod.cash, lines: [line]);
    final s2 = sales.create(method: PaymentMethod.cash, lines: [line]);
    expect([s1.no, s2.no], ['A-1033', 'A-1034']);
    expect(c.read(deviceProvider).nextReceiptNo, 'A-1035');
    expect(c.read(salesProvider).map((s) => s.no).toSet(), hasLength(c.read(salesProvider).length));
  });
}
