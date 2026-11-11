import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/app/fake_database.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/features/sales/data/fake_sales_repository.dart';

void main() {
  test('watch emits the current value, then again after each write', () async {
    final db = seedFakeDatabase('t');
    final repo = FakeSalesRepository(db);
    final seen = <int>[];
    final sub = repo.watchAll().listen((s) => seen.add(s.length));
    await pumpEventQueue();
    final n = seen.single;
    await repo.add(seedSales('t').first);
    await pumpEventQueue();
    expect(seen, [n, n + 1]);
    await sub.cancel();
  });

  test('.first completes (services read through it)', () async {
    final db = seedFakeDatabase('t');
    expect(await FakeSalesRepository(db).watchAll().first, isNotEmpty);
  });

  test('transaction: no emissions mid-way, one on commit, none on rollback', () async {
    final db = seedFakeDatabase('t');
    final repo = FakeSalesRepository(db);
    var emissions = 0;
    final sub = repo.watchAll().listen((_) => emissions++);
    await pumpEventQueue();
    emissions = 0;

    await db.transaction(() async {
      await repo.add(seedSales('t').first);
      await pumpEventQueue();
      expect(emissions, 0, reason: 'held until commit');
      await repo.add(seedSales('t').first);
    });
    await pumpEventQueue();
    expect(emissions, 1, reason: 'one notification per commit');

    final before = db.sales.length;
    await expectLater(
      db.transaction(() async {
        await repo.add(seedSales('t').first);
        throw StateError('boom');
      }),
      throwsStateError,
    );
    await pumpEventQueue();
    expect(emissions, 1, reason: 'rolled-back writes are never announced');
    expect(db.sales.length, before);
    await sub.cancel();
  });

  test('watchers of other tables are not woken', () async {
    final db = seedFakeDatabase('t');
    var hits = 0;
    final sub = db.watch({FakeTable.customers}, () => db.customers.length).listen((_) => hits++);
    await pumpEventQueue();
    await FakeSalesRepository(db).add(seedSales('t').first);
    await pumpEventQueue();
    expect(hits, 1);
    await sub.cancel();
  });
}
