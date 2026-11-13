import '../product_model.dart';
import 'recipe_models.dart';

class IngredientMatcher {
  static RecipePantryAvailability match(
    OfflineRecipe recipe,
    List<Product> pantry, {
    DateTime? now,
  }) {
    final available = <PantryIngredientMatch>[];
    final missing = <RecipeIngredient>[];
    final referenceDate = now ?? DateTime.now();

    for (final ingredient in recipe.ingredients) {
      if (_isKitchenUtility(ingredient.name)) {
        continue;
      }
      final matches = pantry
          .where(
            (product) =>
                _isUsable(product, referenceDate) &&
                _matchesIngredient(ingredient, product),
          )
          .toList();

      if (matches.isEmpty) {
        if (!ingredient.optional) {
          missing.add(ingredient);
        }
      } else {
        available.add(
          PantryIngredientMatch(
            ingredient: ingredient,
            products: matches,
          ),
        );
      }
    }

    return RecipePantryAvailability(
      available: available,
      missing: missing,
    );
  }

  static bool _isKitchenUtility(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'water' || normalized == 'salt';
  }

  static bool _isUsable(Product product, DateTime now) {
    if (product.status.trim().toLowerCase() == 'finished') {
      return false;
    }
    if (_isZeroQuantity(product.quantity)) {
      return false;
    }

    final expiry = _parseDate(product.exp);
    if (expiry != null &&
        expiry.isBefore(DateTime(now.year, now.month, now.day))) {
      return false;
    }
    return true;
  }

  static bool _isZeroQuantity(String quantity) {
    final value = quantity.trim().toLowerCase();
    if (value.isEmpty || value == 'not detected') {
      return false;
    }
    final match = RegExp(r'^0+(?:[.,]0+)?\s*[a-z]*$').firstMatch(value);
    return match != null;
  }

  static bool _matchesIngredient(
    RecipeIngredient ingredient,
    Product product,
  ) {
    final productTokens = _tokens(product.name);
    final names = <String>[
      ingredient.name,
      ...ingredient.aliases,
    ];

    return names.any((name) {
      final ingredientTokens = _tokens(name);
      if (ingredientTokens.isEmpty) return false;
      if (ingredientTokens.length != productTokens.length) return false;
      return _sameTokens(ingredientTokens, productTokens);
    });
  }

  static bool _sameTokens(List<String> left, List<String> right) {
    final normalizedLeft = left.map(_canonicalToken).toList();
    final normalizedRight = right.map(_canonicalToken).toList();
    if (normalizedLeft.length != normalizedRight.length) return false;
    for (var index = 0; index < normalizedLeft.length; index++) {
      if (normalizedLeft[index] != normalizedRight[index]) return false;
    }
    return true;
  }

  static String _canonicalToken(String token) {
    final aliases = <String, String>{
      'tomatoes': 'tomato',
      'onions': 'onion',
      'noodles': 'noodle',
      'cilantro': 'coriander',
      'jeera': 'cumin',
      'haldi': 'turmeric',
      'atta': 'wheat',
    };
    return aliases[token] ?? token;
  }

  static List<String> _tokens(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  static DateTime? _parseDate(String value) {
    final clean = value.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'not detected') return null;
    final match =
        RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(clean);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
