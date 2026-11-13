import 'product_model.dart';
import 'services/ingredient_matcher.dart';
import 'services/offline_recipe_service.dart';
import 'services/recipe_models.dart';

class GeminiService {
  static String buildOfflineRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) {
    final recipe = OfflineRecipeService.find(userQuestion);
    if (recipe == null) {
      return _unsupported(userQuestion);
    }

    final products = pantryItems.map((item) {
      final match =
          RegExp(r'^(.+?)\s*\(([^()]*)\)\s*$').firstMatch(item.trim());
      return Product(
        id: item,
        name: match?.group(1)?.trim() ?? item.trim(),
        quantity: match?.group(2)?.trim() ?? 'Not detected',
        addedDate: DateTime.now(),
      );
    }).toList();
    final availability = IngredientMatcher.match(recipe, products);
    return formatOfflineRecipe(recipe, availability);
  }

  static Future<String> generateRecipeWithContext({
    required String userQuestion,
    required OfflineRecipe? recipe,
    required RecipePantryAvailability? availability,
    String conversationContext = '',
  }) async {
    return recipe == null
        ? _unsupported(userQuestion)
        : formatOfflineRecipe(recipe, availability!);
  }

  static String formatAgentResponse(Map<String, dynamic> response) {
    if (response['status'] != 'ok') {
      final message = response['message']?.toString() ??
          'Online Recipe Agent returned an invalid response.';
      throw FormatException(message);
    }
    String listValue(String key) {
      final values = response[key];
      if (values is! List || values.isEmpty) return 'None';
      return values.map((value) => '- ${_formatValue(value)}').join('\n');
    }

    return '''
🍽️ RECIPE: ${response['dish_name'] ?? 'Requested recipe'}

🌍 CUISINE: ${response['cuisine'] ?? 'Not specified'}
📝 ${response['description'] ?? ''}
🌿 FLAVOR PROFILE: ${response['flavor_profile'] ?? 'Not specified'}
🎯 WHY THESE PANTRY ITEMS: ${response['prioritization_reason'] ?? 'Selected to match the requested recipe.'}
👥 SERVINGS: ${response['servings'] ?? 'Not specified'}
⏱️ PREPARATION TIME: ${response['preparation_time'] ?? 'Not specified'}
🔥 COOKING TIME: ${response['cooking_time'] ?? 'Not specified'}

🥘 REQUIRED INGREDIENTS:
${listValue('required_ingredients')}

🥗 OPTIONAL INGREDIENTS:
${listValue('optional_ingredients')}

🧺 AVAILABLE IN YOUR PANTRY:
${listValue('available_pantry_ingredients')}

🛒 MISSING / NEED TO BUY:
${listValue('missing_ingredients')}

👨‍🍳 PREPARATION:
${listValue('preparation')}

🔥 COOKING METHOD:
${listValue('cooking')}

🍽️ SERVING SUGGESTIONS:
${listValue('serving_suggestions')}

🔄 SUBSTITUTIONS:
${listValue('substitutions')}

⚠️ EXPIRY STATUS:
${listValue('expiry_warnings')}

💡 TIPS:
${listValue('tips')}
''';
  }

  static String _formatValue(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      final name = value['name'] ?? value['dish_name'] ?? '';
      final quantity = value['quantity'];
      final products = value['products'];
      if (products is List && products.isNotEmpty) {
        return '$name: ${products.map(_formatValue).join(', ')}';
      }
      if (quantity != null) return '$name — $quantity';
      if (value['days'] != null) return '$name (${value['days']} days)';
      return name.toString();
    }
    return value.toString();
  }

  static String formatOfflineRecipe(
    OfflineRecipe recipe,
    RecipePantryAvailability availability,
  ) {
    final ingredients = recipe.ingredients
        .map(
          (item) =>
              '- ${item.name} — ${item.quantity}${item.optional ? ' (optional)' : ''}',
        )
        .join('\n');
    final preparation = recipe.preparation
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    final cooking = recipe.cookingMethod
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    final tips = recipe.tips.map((tip) => '- $tip').join('\n');

    return '''
🍽️ RECIPE: ${recipe.name}

👥 SERVINGS: ${recipe.servings}

⏱️ PREPARATION TIME: ${recipe.preparationTime}

🔥 COOKING TIME: ${recipe.cookingTime}

🥘 INGREDIENTS REQUIRED:
$ingredients

${_availabilitySection(availability)}

👨‍🍳 PREPARATION:
$preparation

🔥 COOKING METHOD:
$cooking

💡 TIPS:
${tips.isEmpty ? '- Follow the quantities and cooking times above.' : tips}
''';
  }

  static String _availabilitySection(RecipePantryAvailability availability) {
    final available = availability.available
        .expand(
          (match) => match.products.map(
            (product) =>
                '- ${product.name} — ${product.quantity} (for ${match.ingredient.name})',
          ),
        )
        .join('\n');
    final missing = availability.missing
        .map(
          (item) =>
              '- ${item.name} — ${item.quantity}${item.optional ? ' (optional)' : ''}',
        )
        .join('\n');

    return '''
🧺 AVAILABLE IN YOUR PANTRY:
${available.isEmpty ? 'No matching pantry ingredients.' : available}

🛒 MISSING / NEED TO BUY:
${missing.isEmpty ? 'All required ingredients are available.' : missing}''';
  }

  static String _unsupported(String request) {
    return '⚠️ I cannot generate "$request" offline because it is not in the '
        'supported recipe catalog and Gemini is unavailable.';
  }
}
