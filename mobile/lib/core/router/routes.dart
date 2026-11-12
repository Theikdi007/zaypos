abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const unlock = '/unlock';
  static const dashboard = '/';
  static const sales = '/sales';
  static String sale(String id) => '/sales/$id';
  static String receipt(String id) => '/sales/$id/receipt';
  static const reports = '/reports';
  static const pos = '/pos';
  static const checkout = '/checkout';
  static const products = '/products';
  static const addProduct = '/products/new';
  static const customers = '/customers';
  static const addCustomer = '/customers/new';
  static String customer(String id) => '/customers/$id';
  static const settingsFeatures = '/settings/features';
}
