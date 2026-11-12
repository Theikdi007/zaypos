import '../../app/fake_database.dart';
import 'feature_repository.dart';

class FakeFeatureRepository implements FeatureRepository {
  FakeFeatureRepository(this.db);
  final FakeDatabase db;

  @override
  Stream<Map<String, bool>> watchAll() => db.watch({FakeTable.features}, () => Map.unmodifiable(db.features));

  @override
  Future<void> setAll(Map<String, bool> values) async {
    db.features.addAll(values);
    db.touch({FakeTable.features});
  }
}
