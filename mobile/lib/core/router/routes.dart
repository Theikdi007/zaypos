abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const unlock = '/unlock';
  static const firstSync = '/first-sync';
  static const syncReview = '/settings/sync-review';
  static const devices = '/settings/devices';
  static const pinReset = '/pin-reset';
  static String rejectedUnit(int seq) => '/settings/sync-review/unit/$seq';
  static const dashboard = '/';
  static const sales = '/sales';
  static String sale(String id) => '/sales/$id';
  static String receipt(String id) => '/sales/$id/receipt';
  static const reports = '/reports';
  static const pos = '/pos';
  static const checkout = '/checkout';
  static const products = '/products';

  /// Products without a selling price (Dashboard card).
  static const productsNeedingPrice = '/products?filter=noPrice';

  /// Products filtered to "Stock နည်း" (Dashboard low-stock card).
  static const productsLowStock = '/products?filter=low';
  static const addProduct = '/products/new';
  static const customers = '/customers';
  static const addCustomer = '/customers/new';
  static String customer(String id) => '/customers/$id';
  static const settingsFeatures = '/settings/features';
}
