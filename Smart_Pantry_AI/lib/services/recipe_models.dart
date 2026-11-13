import '../product_model.dart';

enum RecipeMode {
  pantryCooking,
  normalChat,
}

class RecipeIngredient {
  final String name;
  final String quantity;
  final bool optional;
  final List<String> aliases;

  const RecipeIngredient({
    required this.name,
    required this.quantity,
    this.optional = false,
    this.aliases = const [],
  });
}

class OfflineRecipe {
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<String> preparation;
  final List<String> cookingMethod;
  final String preparationTime;
  final String cookingTime;
  final String servings;
  final List<String> tips;

  const OfflineRecipe({
    required this.name,
    required this.ingredients,
    required this.preparation,
    required this.cookingMethod,
    required this.preparationTime,
    required this.cookingTime,
    required this.servings,
    this.tips = const [],
  });
}

class PantryIngredientMatch {
  final RecipeIngredient ingredient;
  final List<Product> products;

  const PantryIngredientMatch({
    required this.ingredient,
    required this.products,
  });
}

class RecipePantryAvailability {
  final List<PantryIngredientMatch> available;
  final List<RecipeIngredient> missing;

  const RecipePantryAvailability({
    required this.available,
    required this.missing,
  });
}
