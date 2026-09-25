import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_model.dart';
import 'meal_model.dart';
import 'shopping_model.dart';
import 'notification_service.dart';

class StorageService {
  static const String _key = 'pantry_products';
  static const String _shoppingKey = 'shopping_list';
  static const String _mealPlanKey = 'meal_plan';
  static const String _mealDetailsKey = 'meal_plan_details';

  static bool get _firebaseReady => Firebase.apps.isNotEmpty;

  static FirebaseFirestore get _firestore {
    if (!_firebaseReady) {
      throw StateError('Firebase has not been initialized.');
    }
    return FirebaseFirestore.instance;
  }

  static User? get _currentUser {
    if (!_firebaseReady) {
      return null;
    }
    return FirebaseAuth.instance.currentUser;
  }

  static DocumentReference<Map<String, dynamic>>? _userDocRef() {
    if (!_firebaseReady) {
      return null;
    }

    final uid = _currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return null;
    }

    return _firestore.collection('users').doc(uid);
  }

  static Future<void> _saveLocalProducts(List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();
    final list = products.map((product) => product.toJson()).toList();
    await prefs.setStringList(_key, list);
  }

  static Future<List<Product>> _loadLocalProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);

    if (list == null || list.isEmpty) {
      return [];
    }

    final products = <Product>[];
    for (final item in list) {
      try {
        products.add(Product.fromJson(item));
      } catch (_) {
        // Ignore corrupted product data instead of crashing the app.
      }
    }

    return products;
  }

  static Future<void> _saveLocalShoppingList(List<ShoppingItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final list = items.map((item) => item.toJson()).toList();
    await prefs.setStringList(_shoppingKey, list);
  }

  static Future<List<ShoppingItem>> _loadLocalShoppingList() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_shoppingKey);

    if (list == null || list.isEmpty) {
      return [];
    }

    final items = <ShoppingItem>[];
    for (final item in list) {
      try {
        items.add(ShoppingItem.fromJson(item));
      } catch (_) {
        // Ignore corrupted shopping-list data.
      }
    }

    return items;
  }

  static Future<void> _saveLocalMealPlan(Map<String, String> mealPlan) async {
    final prefs = await SharedPreferences.getInstance();
    final data = Map<String, String>.from(mealPlan);
    final encoded = jsonEncode(data);
    await prefs.setString(_mealPlanKey, encoded);
  }

  static Future<Map<String, String>> _loadLocalMealPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_mealPlanKey);

    if (encoded == null || encoded.isEmpty) {
      return {};
    }

    try {
      final raw = jsonDecode(encoded);
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
    } catch (_) {
      // Ignore corrupted meal plan data.
    }

    return {};
  }

  static Future<void> _saveLocalMeals(Map<String, List<Meal>> meals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mealDetailsKey,
      jsonEncode(meals.map((day, entries) => MapEntry(
            day,
            entries.map((meal) => meal.toMap()).toList(),
          ))),
    );
  }

  static Future<Map<String, List<Meal>>> _loadLocalMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_mealDetailsKey);
    if (encoded == null || encoded.isEmpty) return {};

    try {
      final raw = jsonDecode(encoded);
      if (raw is Map) {
        return raw.map((day, entries) {
          final meals = entries is List
              ? entries
                  .whereType<Map>()
                  .map((item) => Meal.fromMap(Map<String, dynamic>.from(item)))
                  .toList()
              : <Meal>[];
          return MapEntry(day.toString(), meals);
        });
      }
    } catch (_) {
      // Ignore corrupted meal details.
    }
    return {};
  }

  // ============================================================
  // PANTRY PRODUCTS
  // ============================================================

  /// Save all pantry products to Firestore for the signed-in user, or fall back
  /// to local storage when no authenticated user is available.
  static Future<void> saveProducts(List<Product> products) async {
    final ref = _userDocRef();
    if (ref != null) {
      await ref.set(
        {
          'pantry': products.map((product) => product.toMap()).toList(),
        },
        SetOptions(merge: true),
      );
      await NotificationService.syncProducts(products);
      return;
    }

    await _saveLocalProducts(products);
    await NotificationService.syncProducts(products);
  }

  /// Load all pantry products from Firestore for the signed-in user, or from
  /// local storage when no authenticated user is available.
  static Future<List<Product>> loadProducts() async {
    final ref = _userDocRef();
    if (ref != null) {
      final snapshot = await ref.get();
      final data = snapshot.data();
      final rawList = data?['pantry'];

      if (rawList is List) {
        final products = <Product>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              products.add(Product.fromMap(Map<String, dynamic>.from(item)));
            } catch (_) {
              // Ignore corrupted product data instead of crashing the app.
            }
          }
        }
        return products;
      }

      return [];
    }

    return _loadLocalProducts();
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

  /// Returns the current pantry as a serializable list for the agent.
  static Future<List<Map<String, dynamic>>> getPantrySnapshot() async {
    final products = await loadProducts();
    return products.map((product) => product.toMap()).toList();
  }

  /// Reduce quantity for a product by a given amount.
  static Future<void> reduceProductQuantity(
    String productId,
    double quantityDeduction,
  ) async {
    final products = await loadProducts();
    final index = products.indexWhere((product) => product.id == productId);

    if (index == -1) {
      return;
    }

    final product = products[index];
    final current = double.tryParse(
          product.quantity.replaceAll(RegExp(r'[^0-9.\-]'), ''),
        ) ??
        0.0;

    final remaining = current - quantityDeduction;
    final updated = product.copyWith(
      quantity: remaining <= 0 ? '0' : remaining.toStringAsFixed(2),
      status: remaining <= 0 ? 'Finished' : product.status,
    );

    products[index] = updated;
    await saveProducts(products);
  }

  static Future<void> recordConsumptionEvent({
    required Product product,
    required String usedQuantity,
    String source = 'Weekly Pantry Check',
  }) async {
    final ref = _userDocRef();
    final event = {
      'productId': product.id,
      'productName': product.name,
      'usedQuantity': usedQuantity,
      'date': DateTime.now().toIso8601String(),
      'source': source,
    };

    if (ref != null) {
      final snapshot = await ref.get();
      final data = snapshot.data();
      final existing = data?['consumptionEvents'] is List
          ? List<dynamic>.from(data!['consumptionEvents'] as List)
          : <dynamic>[];
      existing.add(event);
      await ref.set(
        {'consumptionEvents': existing},
        SetOptions(merge: true),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString('consumption_events');
    final existing = encoded == null ? <dynamic>[] : (jsonDecode(encoded) as List<dynamic>);
    existing.add(event);
    await prefs.setString('consumption_events', jsonEncode(existing));
  }

  // ============================================================
  // SHOPPING LIST
  // ============================================================

  /// Save shopping list to Firestore for the signed-in user, or fallback to
  /// local storage when no authenticated user is available.
  static Future<void> saveShoppingList(
    List<ShoppingItem> items,
  ) async {
    final ref = _userDocRef();
    if (ref != null) {
      try {
        await ref.set(
          {
            'shoppingList': items.map((item) => item.toMap()).toList(),
          },
          SetOptions(merge: true),
        );
        return;
      } catch (_) {
        await _saveLocalShoppingList(items);
        return;
      }
    }

    await _saveLocalShoppingList(items);
  }

  /// Load shopping list from Firestore for the signed-in user, or from local
  /// storage when no authenticated user is available.
  static Future<List<ShoppingItem>> loadShoppingList() async {
    final ref = _userDocRef();
    if (ref != null) {
      final snapshot = await ref.get();
      final data = snapshot.data();
      final rawList = data?['shoppingList'];

      if (rawList is List) {
        final items = <ShoppingItem>[];
        for (final item in rawList) {
          if (item is Map) {
            try {
              items.add(ShoppingItem.fromMap(Map<String, dynamic>.from(item)));
            } catch (_) {
              // Ignore corrupted shopping-list data.
            }
          }
        }
        return items;
      }

      return [];
    }

    return _loadLocalShoppingList();
  }

  /// Appends new shopping items to the current list without duplicates.
  static Future<void> addShoppingItems(List<String> items) async {
    final existing = await loadShoppingList();
    final names = existing.map((item) => item.name.toLowerCase()).toSet();

    final unique = <ShoppingItem>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (!names.contains(trimmed.toLowerCase())) {
        unique.add(
          ShoppingItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: trimmed,
          ),
        );
        names.add(trimmed.toLowerCase());
      }
    }

    final combined = [...existing, ...unique];
    await saveShoppingList(combined);
  }

  static Future<void> saveMeals(Map<String, List<Meal>> meals) async {
    final data = meals.map((day, entries) => MapEntry(
          day,
          entries.map((meal) => meal.toMap()).toList(),
        ));
    final ref = _userDocRef();
    if (ref != null) {
      try {
        await ref.set({'mealPlanDetails': data}, SetOptions(merge: true));
        return;
      } catch (_) {
        // Keep the meal plan available when Firestore is offline or unavailable.
        await _saveLocalMeals(meals);
        return;
      }
    }
    await _saveLocalMeals(meals);
  }

  static Future<Map<String, List<Meal>>> loadMeals() async {
    final ref = _userDocRef();
    if (ref != null) {
      try {
        final snapshot = await ref.get();
        final raw = snapshot.data()?['mealPlanDetails'];
        if (raw is Map) {
          return raw.map((day, entries) {
            final meals = entries is List
                ? entries
                    .whereType<Map>()
                    .map((item) => Meal.fromMap(Map<String, dynamic>.from(item)))
                    .toList()
                : <Meal>[];
            return MapEntry(day.toString(), meals);
          });
        }
      } catch (_) {
        // Fall through to local storage when Firestore cannot be read.
      }
      return _loadLocalMeals();
    }
    return _loadLocalMeals();
  }

  static Future<void> saveMealPlan(Map<String, String> mealPlan) async {
    final ref = _userDocRef();
    if (ref != null) {
      await ref.set(
        {'mealPlan': mealPlan},
        SetOptions(merge: true),
      );
      return;
    }

    await _saveLocalMealPlan(mealPlan);
  }

  static Future<Map<String, String>> loadMealPlan() async {
    final ref = _userDocRef();
    if (ref != null) {
      final snapshot = await ref.get();
      final data = snapshot.data();
      final raw = data?['mealPlan'];

      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
      }

      return {};
    }

    return _loadLocalMealPlan();
  }

  static Future<void> migrateLocalDataToFirestore() async {
    if (!_firebaseReady) {
      return;
    }

    final ref = _userDocRef();
    if (ref == null) {
      return;
    }

    final localProducts = await _loadLocalProducts();
    final localShopping = await _loadLocalShoppingList();
    final localMealPlan = await _loadLocalMealPlan();

    if (localProducts.isEmpty && localShopping.isEmpty && localMealPlan.isEmpty) {
      return;
    }

    final snapshot = await ref.get();
    final existing = snapshot.data() ?? {};

    final remotePantry = existing['pantry'] is List
        ? List<Map<String, dynamic>>.from(
            (existing['pantry'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)),
          )
        : <Map<String, dynamic>>[];

    final remoteShopping = existing['shoppingList'] is List
        ? List<Map<String, dynamic>>.from(
            (existing['shoppingList'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)),
          )
        : <Map<String, dynamic>>[];

    final remoteMealPlan = existing['mealPlan'] is Map
        ? existing['mealPlan'] as Map<String, dynamic>
        : <String, dynamic>{};

    final pantryToSave = remotePantry.isEmpty && localProducts.isNotEmpty
        ? localProducts.map((product) => product.toMap()).toList()
        : remotePantry;

    final shoppingToSave = remoteShopping.isEmpty && localShopping.isNotEmpty
        ? localShopping.map((item) => item.toMap()).toList()
        : remoteShopping;

    final mealPlanToSave = remoteMealPlan.isEmpty && localMealPlan.isNotEmpty
        ? localMealPlan
        : remoteMealPlan;

    await ref.set(
      {
        if (localProducts.isNotEmpty || remotePantry.isNotEmpty)
          'pantry': pantryToSave,
        if (localShopping.isNotEmpty || remoteShopping.isNotEmpty)
          'shoppingList': shoppingToSave,
        if (localMealPlan.isNotEmpty || remoteMealPlan.isNotEmpty)
          'mealPlan': mealPlanToSave,
      },
      SetOptions(merge: true),
    );

    await NotificationService.syncProducts(
      pantryToSave.map(Product.fromMap).toList(),
    );
  }
}