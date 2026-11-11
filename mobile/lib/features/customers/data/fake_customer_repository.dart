import '../../../app/fake_seed.dart';
import '../domain/customer.dart';
import 'customer_repository.dart';

class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({required this.tenantId}) {
    Customer c(String id, String name, String phone, DateTime at, {String? address}) => Customer(
          id: id,
          tenantId: tenantId,
          name: name,
          phone: phone,
          address: address,
          createdAt: at,
          updatedAt: at,
        );
    final at = daysAgoAt(60, 9, 0);
    _items.addAll([
      c(SeedIds.thanHtun, 'ဦးသန်းထွန်း', '09 4xx xxx 880', at),
      c(SeedIds.khinMa, 'ဒေါ်ခင်မာ', '09 7xx xxx 102', at),
      c(SeedIds.aungKyaw, 'ဦးအောင်ကျော်', '09 7xx xxx 214', at, address: 'ရပ်ကွက် (၅)'),
      c(SeedIds.zawMin, 'ကိုဇော်မင်း', '09 2xx xxx 655', at),
      c(SeedIds.niNi, 'ဒေါ်နီနီ', '09 9xx xxx 431', at),
      c(SeedIds.myatNoe, 'မမြတ်နိုး', '09 4xx xxx 017', at),
      c(SeedIds.htet, 'ကိုထက်', '09 2xx xxx 390', at),
    ]);
  }

  final String tenantId;
  final _items = <Customer>[];

  @override
  List<Customer> list() => List.unmodifiable(_items.where((c) => c.deletedAt == null));

  @override
  void add(Customer customer) => _items.add(customer);
}
