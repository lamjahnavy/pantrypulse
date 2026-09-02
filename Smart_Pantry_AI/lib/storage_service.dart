import 'package:shared_preferences/shared_preferences.dart';
import 'product_model.dart';
import 'shopping_model.dart';

class StorageService {
  static const String _key = 'pantry_products';
  static const String _shoppingKey = 'shopping_list';

  // ============================================================
  // PANTRY PRODUCTS
  // ============================================================

  /// Save all pantry products
  static Future<void> saveProducts(List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> list =
        products.map((product) => product.toJson()).toList();

    await prefs.setStringList(_key, list);
  }

  /// Load all pantry products
  static Future<List<Product>> loadProducts() async {
    final prefs = await SharedPreferences.getInstance();

    final List<String>? list = prefs.getStringList(_key);

    if (list == null || list.isEmpty) {
      return [];
    }

    final List<Product> products = [];

    for (final item in list) {
      try {
        products.add(Product.fromJson(item));
      } catch (e) {
        // Ignore corrupted product data instead of crashing the app.
      }
    }

    return products;
  }

  /// Add one product to the existing pantry
  static Future<void> addProduct(Product product) async {
    final products = await loadProducts();

    products.add(product);

    await saveProducts(products);
  }

  /// Delete a product using its ID
  static Future<void> deleteProduct(String productId) async {
    final products = await loadProducts();

    products.removeWhere((product) => product.id == productId);

    await saveProducts(products);
  }

  /// Update an existing product
  static Future<void> updateProduct(Product updatedProduct) async {
    final products = await loadProducts();

    final index = products.indexWhere(
      (product) => product.id == updatedProduct.id,
    );

    if (index != -1) {
      products[index] = updatedProduct;
    }

    await saveProducts(products);
  }

  // ============================================================
  // SHOPPING LIST
  // ============================================================

  /// Save shopping list
  static Future<void> saveShoppingList(
    List<ShoppingItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> list =
        items.map((item) => item.toJson()).toList();

    await prefs.setStringList(_shoppingKey, list);
  }

  /// Load shopping list
  static Future<List<ShoppingItem>> loadShoppingList() async {
    final prefs = await SharedPreferences.getInstance();

    final List<String>? list =
        prefs.getStringList(_shoppingKey);

    if (list == null || list.isEmpty) {
      return [];
    }

    final List<ShoppingItem> items = [];

    for (final item in list) {
      try {
        items.add(ShoppingItem.fromJson(item));
      } catch (e) {
        // Ignore corrupted shopping-list data.
      }
    }

    return items;
  }
}