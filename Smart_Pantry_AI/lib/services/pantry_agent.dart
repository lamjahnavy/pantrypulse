import '../recipe_service.dart';
import '../storage_service.dart';

class PantryAgentToolResult {
  final bool success;
  final String message;
  final Map<String, dynamic> data;

  const PantryAgentToolResult({
    required this.success,
    required this.message,
    this.data = const {},
  });
}

class PantryAgent {
  static const String modelName = 'gemini-3.6-flash';

  static Future<Map<String, dynamic>> getPantryItems() async {
    final items = await StorageService.loadProducts();
    final result = items.map((item) => item.toMap()).toList();
    return {
      'items': result,
      'count': result.length,
    };
  }

  static Future<Map<String, dynamic>> getExpiringItems({
    int daysAhead = 7,
  }) async {
    final items = await StorageService.loadProducts();
    final today = DateTime.now();

    final filtered = <Map<String, dynamic>>[];

    for (final item in items) {
      final exp = item.exp;
      if (exp == 'Not detected') {
        continue;
      }

      try {
        final parsed = _parseDate(exp);
        final diff = parsed.difference(today).inDays;
        if (diff <= daysAhead) {
          filtered.add(item.toMap());
        }
      } catch (_) {
        // Ignore invalid dates so the app does not crash.
      }
    }

    return {
      'items': filtered,
      'count': filtered.length,
      'daysAhead': daysAhead,
    };
  }

  static Future<Map<String, dynamic>> generateRecipe({
    required List<String> ingredients,
    required String userPreference,
  }) async {
    final combined = ingredients.isEmpty
        ? 'No pantry ingredients were provided.'
        : ingredients.join(', ');

    final text = userPreference.trim().isEmpty
        ? 'Generate a practical recipe using the provided ingredients.'
        : userPreference.trim();

    final response = await RecipeService.generateRecipe(
      '$text\n\nAvailable ingredients: $combined',
    );

    return {
      'success': true,
      'recipe': response,
    };
  }

  static Future<Map<String, dynamic>> addToShoppingList({
    required List<String> items,
  }) async {
    if (items.isEmpty) {
      return {
        'success': true,
        'message': 'No shopping items to add.',
        'added': 0,
      };
    }

    final before = await StorageService.loadShoppingList();
    final names = before.map((item) => item.name.toLowerCase()).toSet();
    final toAdd = <String>[];

    for (final item in items) {
      final clean = item.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (!names.contains(clean.toLowerCase())) {
        toAdd.add(clean);
      }
    }

    if (toAdd.isEmpty) {
      return {
        'success': true,
        'message': 'All items already exist in the shopping list.',
        'added': 0,
      };
    }

    await StorageService.addShoppingItems(toAdd);

    return {
      'success': true,
      'message': 'Shopping list updated.',
      'added': toAdd.length,
      'items': toAdd,
    };
  }

  static Future<Map<String, dynamic>> updatePantryQuantity({
    required String productId,
    required double quantityDeduction,
  }) async {
    if (productId.trim().isEmpty) {
      return {
        'success': false,
        'message': 'Product id is required.',
      };
    }

    if (quantityDeduction <= 0) {
      return {
        'success': false,
        'message': 'The deduction must be positive.',
      };
    }

    await StorageService.reduceProductQuantity(productId, quantityDeduction);

    return {
      'success': true,
      'message': 'Pantry quantity updated.',
      'productId': productId,
      'deduction': quantityDeduction,
    };
  }

  static Future<String> runAgenticMealPlan({
    required String userRequest,
    int expiryWindowDays = 7,
  }) async {
    try {
      final pantry = await getPantryItems();
      final items = pantry['items'] as List<dynamic>? ?? const [];
      final pantryList = items
          .map((item) => item is Map<String, dynamic>
              ? item['name']?.toString() ?? ''
              : '')
          .where((name) => name.isNotEmpty)
          .toList();

      final expiring = await getExpiringItems(daysAhead: expiryWindowDays);
      final expiringNames = (expiring['items'] as List<dynamic>? ?? const [])
          .map((item) => item is Map<String, dynamic>
              ? item['name']?.toString() ?? ''
              : '')
          .where((name) => name.isNotEmpty)
          .toList();

      final prompt = '''
You are Pantry Pulse Agent.

User request: $userRequest

Current pantry items: ${pantryList.isEmpty ? 'No pantry items.' : pantryList.join(', ')}
Expiring soon: ${expiringNames.isEmpty ? 'None.' : expiringNames.join(', ')}

Use a ReAct workflow:
1. Decide the user's actual intent.
2. Prioritize expiring items first if the user asks for a meal suggestion.
3. Respect the specified dish when the user names one.
4. Mention missing ingredients, then offer to add them to the shopping list if needed.
5. Do not invent pantry state.
6. Keep output practical and concise.
''';

      final recipeText = await RecipeService.generateRecipe(prompt);
      final missingText = expiringNames.isEmpty
          ? 'No urgent expiry items found.'
          : 'Urgent expiry items: ${expiringNames.join(', ')}';

      return '$recipeText\n\n$missingText';
    } catch (e) {
      return 'Agent failed to reason about pantry state: $e';
    }
  }

  static DateTime _parseDate(String raw) {
    final value = raw.trim();
    final clean = value
        .replaceAll(' ', '')
        .replaceAll('.', '/')
        .replaceAll('-', '/');

    final candidates = [
      'dd/MM/yyyy',
      'dd/MM/yy',
      'MM/dd/yyyy',
      'MM/dd/yy',
    ];

    for (final format in candidates) {
      try {
        return _parseByPattern(clean, format);
      } catch (_) {
        // Try next pattern.
      }
    }

    final monthMatch = RegExp(
      r'^(\d{1,2})\s*/?\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s*/?\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(value);

    if (monthMatch != null) {
      final day = int.parse(monthMatch.group(1)!);
      final month = _monthToInt(monthMatch.group(2)!);
      final year = int.parse(monthMatch.group(3)!);
      return DateTime(year, month, day);
    }

    throw FormatException('Unsupported date format: $raw');
  }

  static DateTime _parseByPattern(String value, String pattern) {
    final day = pattern == 'dd/MM/yyyy' || pattern == 'dd/MM/yy'
        ? int.parse(value.split('/')[0])
        : int.parse(value.split('/')[1]);

    final month = pattern == 'dd/MM/yyyy' || pattern == 'dd/MM/yy'
        ? int.parse(value.split('/')[1])
        : int.parse(value.split('/')[0]);

    final yearPart = value.split('/')[2];
    final year = yearPart.length == 2 ? 2000 + int.parse(yearPart) : int.parse(yearPart);

    return DateTime(year, month, day);
  }

  static int _monthToInt(String month) {
    const map = {
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12,
    };
    return map[month.toUpperCase()] ?? 1;
  }
}
