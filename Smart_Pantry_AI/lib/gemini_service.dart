import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiService {
  // ============================================================
  //
  // Prefer an environment variable when running in VS Code/CLI:
  // flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY
  // Keep credentials out of source control.
  // ============================================================
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static String buildOfflineRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) {
    final request = userQuestion.trim();
    final normalized = request.isEmpty ? 'recipe' : request.toLowerCase();
    final dishName = _extractDishName(normalized);
    final relevantPantry = _filterRelevantPantry(dishName, pantryItems);
    final ingredients = relevantPantry.isEmpty
        ? <String>[
            '2 tbsp oil',
            '1 onion',
            '2 tomatoes',
            '1 tsp ginger-garlic paste',
            '1 tsp curry powder',
            '250 g chicken',
            'salt to taste',
          ]
        : relevantPantry
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();

    final missing = <String>[];
    if (!ingredients.any((item) => item.toLowerCase().contains('chicken'))) {
      missing.add('250 g chicken');
    }
    if (!ingredients.any((item) => item.toLowerCase().contains('onion'))) {
      missing.add('1 onion');
    }
    if (!ingredients.any((item) => item.toLowerCase().contains('tomato'))) {
      missing.add('2 tomatoes');
    }
    if (!ingredients.any((item) => item.toLowerCase().contains('oil'))) {
      missing.add('2 tbsp oil');
    }

    final ingredientList = ingredients.isNotEmpty
        ? ingredients.map((item) => '- $item').join('\n')
        : '- 2 tbsp oil\n- 1 onion\n- 2 tomatoes\n- 250 g chicken\n- 1 tsp curry powder\n- salt to taste';

    final pantryLine = relevantPantry.isEmpty
        ? 'No pantry information available.'
      : 'Pantry items available: ${relevantPantry.join(', ')}';

    return '''
🍽️ RECIPE: $dishName

👥 SERVINGS: 2–3

⏱️ PREPARATION TIME: 15 minutes

🔥 COOKING TIME: 25 minutes

🥘 INGREDIENTS:
$ingredientList

🧺 AVAILABLE IN YOUR PANTRY:
$pantryLine

🛒 MISSING / NEED TO BUY:
${missing.isEmpty ? 'All required ingredients are available.' : missing.map((item) => '- $item').join('\n')}

👨‍🍳 PREPARATION:
1. Heat oil in a pan and sauté the onion until lightly golden.
2. Add ginger-garlic paste and cook for 1 minute until fragrant.
3. Stir in the tomatoes and curry powder, then cook until the masala thickens.
4. Add chicken pieces and salt, and cook until the chicken starts to brown.
5. Add a splash of water, cover, and cook until the chicken is tender.

🔥 COOKING METHOD:
1. Simmer on low heat for 10–15 minutes until the curry is rich and glossy.
2. Taste and adjust salt, spice, and water as needed.
3. Finish with fresh herbs if available and serve hot with rice or roti.

💡 TIPS:
- Use a lid to keep the curry moist and tender.
- If the sauce is too thick, add a little warm water.
- For extra depth, add a pinch of garam masala at the end.
''';
  }

  static List<String> _filterRelevantPantry(
    String dishName,
    List<String> pantryItems,
  ) {
    if (pantryItems.isEmpty) return [];

    final dishWords = dishName.toLowerCase().split(RegExp(r'\s+'));
    final allowed = <String>{
      'chicken', 'mutton', 'fish', 'prawn', 'egg', 'paneer', 'tofu',
      'rice', 'flour', 'atta', 'noodle', 'noodles', 'pasta', 'bread',
      'onion', 'tomato', 'potato', 'garlic', 'ginger', 'chilli', 'chili',
      'pepper', 'salt', 'sugar', 'oil', 'ghee', 'butter', 'milk', 'curd',
      'yogurt', 'cream', 'coconut', 'lemon', 'lime', 'coriander', 'mint',
      'cumin', 'jeera', 'mustard', 'turmeric', 'haldi', 'masala', 'spice',
      'dal', 'lentil', 'vegetable', 'carrot', 'peas', 'beans',
    };

    if (dishWords.contains('chicken')) {
      allowed.remove('sugar');
      allowed.remove('mustard');
    }

    final result = <String>[];
    for (final item in pantryItems) {
      final value = item.trim();
      final words = value.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
      if (words.any(allowed.contains) ||
          dishWords.any((word) => word.length > 2 && value.toLowerCase().contains(word))) {
        result.add(value);
      }
    }
    return result;
  }

  static String _extractDishName(String normalized) {
    if (normalized.contains('biryani')) return 'Chicken Biryani';
    if (normalized.contains('curry')) return 'Chicken Curry';
    if (normalized.contains('paneer')) return 'Paneer Curry';
    if (normalized.contains('dal')) return 'Dal';
    if (normalized.contains('maggi')) return 'Maggi';
    if (normalized.contains('pasta')) return 'Pasta';
    if (normalized.contains('omelet')) return 'Omelet';
    if (normalized.contains('fried rice')) return 'Fried Rice';
    if (normalized.contains('sandwich')) return 'Sandwich';
    return 'Quick Home Recipe';
  }

  // Current stable Gemini model.
  static const String model = 'gemini-3.6-flash';

  // ============================================================
  // GENERATE RECIPE

  static Future<String> generateRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) async {
    final question = userQuestion.trim();

    if (question.isEmpty) {
      return '''
❌ Please enter a recipe request.

For example:
• How can I make chicken biryani?
• How can I make chicken curry?
• How can I make palak paneer?
• How can I make dal?
• How can I make Maggi?
''';
    }

    final relevantPantry = _filterRelevantPantry(
      _extractDishName(question),
      pantryItems,
    );
    final pantryText = relevantPantry.isEmpty
        ? 'The pantry is currently empty or no pantry information was provided.'
        : relevantPantry.join(', ');

    final prompt = '''
You are Chef AI, an expert Indian and international cooking assistant.

The user is asking for a recipe.

============================================================
USER REQUEST
============================================================

$userQuestion

============================================================
PANTRY INFORMATION
============================================================

The user's current pantry contains:

$pantryText

============================================================
MOST IMPORTANT RULE
============================================================

FIRST understand the EXACT dish the user requested.

The requested dish has priority over the pantry.

The pantry must NEVER change the requested dish.

Examples:

User asks:
"How can I make chicken biryani?"

You MUST give:
Chicken Biryani

You MUST NOT give:
Vegetable Biryani
Paneer Biryani
Egg Biryani
Veg Pulao

User asks:
"How can I make chicken curry?"

You MUST give:
Chicken Curry

You MUST NOT give:
Vegetable Curry
Paneer Curry
Dal

User asks:
"How can I make palak paneer?"

You MUST give:
Palak Paneer

User asks:
"How can I make dal?"

You MUST give:
Dal

User asks:
"How can I make Maggi?"

You MUST give:
Maggi

============================================================
PANTRY RULE
============================================================

The pantry is ONLY used to tell the user which ingredients they
already have and which ingredients they need to buy.

Only list pantry items that are relevant ingredients or useful components
for the exact requested dish. Never list unrelated pantry products under
AVAILABLE IN YOUR PANTRY. For example, do not list mustard seeds or sugar
for Chicken Curry unless the recipe specifically requires them.

Do NOT replace the requested recipe because an ingredient is missing.

For example:

If the user asks for Chicken Biryani and the pantry contains only:

Rice, Onion, Salt

You should STILL provide a complete Chicken Biryani recipe.

Then clearly say:

AVAILABLE FROM PANTRY:
- Rice
- Onion
- Salt

MISSING / NEED TO BUY:
- Chicken
- Biryani masala
- Ginger-garlic paste
- Yogurt
- etc.

Then provide the complete cooking instructions.

The user should be able to go to the shop, buy the missing ingredients,
and make the requested dish.

============================================================
RECIPE QUALITY
============================================================

Give a REAL, PRACTICAL recipe.

Do not give generic instructions such as:

"Follow standard cooking techniques."

Instead give actual cooking instructions.

For example, for Chicken Biryani:

1. Wash and soak the rice.
2. Marinate the chicken.
3. Heat oil in a heavy-bottomed pot.
4. Fry onions until golden.
5. Add whole spices.
6. Add ginger-garlic paste.
7. Add chicken and cook.
8. Add yogurt and spices.
9. Add partially cooked rice.
10. Layer and cook on low flame.
11. Rest the biryani.
12. Gently mix and serve.

Use appropriate ingredients and steps for the EXACT requested dish.

============================================================
IMPORTANT
============================================================

- NEVER substitute a requested meat dish with a vegetarian dish.
- NEVER substitute chicken with vegetables.
- NEVER substitute the requested dish with something similar.
- NEVER generate Vegetable Biryani when Chicken Biryani was requested.
- NEVER generate a generic answer for a clearly specified dish.
- NEVER say that you cannot make the recipe just because pantry items
  are missing.
- Always provide the complete recipe.
- Always identify missing ingredients when pantry information is available.
- Always give quantities.
- Always give cooking times.
- Always give practical step-by-step instructions.
- If the user asks for a specific dish, the recipe title must match that dish.
- If the user's spelling has a small error, understand the intended dish.

============================================================
RESPONSE FORMAT
============================================================

🍽️ RECIPE: [EXACT DISH NAME]

👥 SERVINGS:
[Number of servings]

⏱️ PREPARATION TIME:
[Time]

🔥 COOKING TIME:
[Time]

🥘 INGREDIENTS:

- Ingredient — quantity
- Ingredient — quantity
- Ingredient — quantity
- Ingredient — quantity

🧺 AVAILABLE IN YOUR PANTRY:

- [ingredient]
- [ingredient]

If no pantry information is available, say:
"No pantry information available."

🛒 MISSING / NEED TO BUY:

- [ingredient]
- [ingredient]

If everything is available, say:
"All required ingredients are available."

👨‍🍳 PREPARATION:

1. [Detailed preparation step]
2. [Detailed preparation step]
3. [Detailed preparation step]

🔥 COOKING METHOD:

1. [Detailed cooking step]
2. [Detailed cooking step]
3. [Detailed cooking step]
4. [Detailed cooking step]
5. [Detailed cooking step]

💡 TIPS:

- [Useful practical tip]
- [Useful practical tip]
- [Useful practical tip]

============================================================
FINAL CHECK
============================================================

Before answering, silently check:

1. What exact dish did the user request?
2. Does my recipe match that exact dish?
3. Did I accidentally change chicken to vegetable?
4. Did I accidentally change curry to another curry?
5. Did I use pantry only for availability/missing ingredients?
6. Did I provide the complete recipe?
7. Did I provide actual cooking steps?

Now answer the user's request.
''';

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );

    try {
      if (apiKey.trim().isEmpty) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      late http.Response response;
      for (var attempt = 0; attempt < 3; attempt++) {
        response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {
                        'text': prompt,
                      },
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': 0.2,
                  'maxOutputTokens': 1800,
                },
              }),
            )
            .timeout(const Duration(seconds: 90));

        if (response.statusCode != 429 && response.statusCode != 503) {
          break;
        }

        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(seconds: 1 << attempt),
          );
        }
      }

      if (response.statusCode != 200) {
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage =
              errorData['error']?['message'] ?? 'Unknown Gemini API error';

          return '''
⚠️ Gemini is unavailable right now, so Chef AI switched to a local recipe fallback.

$errorMessage

${buildOfflineRecipe(userQuestion, pantryItems: pantryItems)}
''';
        } catch (_) {
          return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
        }
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      final candidates = data['candidates'];

      if (candidates == null ||
          candidates is! List ||
          candidates.isEmpty) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      final firstCandidate = candidates.first;

      if (firstCandidate is! Map) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      final content = firstCandidate['content'];

      if (content == null || content is! Map) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      final parts = content['parts'];

      if (parts == null ||
          parts is! List ||
          parts.isEmpty) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      final buffer = StringBuffer();

      for (final part in parts) {
        if (part is Map && part['text'] != null) {
          buffer.write(part['text'].toString());
        }
      }

      final result = buffer.toString().trim();

      if (result.isEmpty) {
        return buildOfflineRecipe(userQuestion, pantryItems: pantryItems);
      }

      return result;
    } on TimeoutException {
      return '''
⚠️ Chef AI timed out, so a local fallback recipe is being shown.

${buildOfflineRecipe(userQuestion, pantryItems: pantryItems)}
''';
    } catch (e) {
      return '''
⚠️ Chef AI could not reach Gemini.

Using a local fallback recipe instead.

${buildOfflineRecipe(userQuestion, pantryItems: pantryItems)}
''';
    }
  }
}