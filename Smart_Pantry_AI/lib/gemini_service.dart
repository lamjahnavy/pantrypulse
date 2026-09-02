import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  // ============================================================
  // GEMINI API KEY
  //
  // Run the app using:
  // flutter run --dart-define=GEMINI_API_KEY=YOUR_NEW_API_KEY
  //
  // Do NOT put your real API key directly into this file.
  // ============================================================
  static const String apiKey =
      String.fromEnvironment('GEMINI_API_KEY');

  // Current stable Gemini model.
  static const String model = 'gemini-3.6-flash';

  // ============================================================
  // GENERATE RECIPE
  // ============================================================

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

    final pantryText = pantryItems.isEmpty
        ? 'The pantry is currently empty or no pantry information was provided.'
        : pantryItems.join(', ');

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
        return '''
❌ Gemini API key is not configured.

Please run the app with:

flutter run --dart-define=GEMINI_API_KEY=YOUR_NEW_API_KEY
''';
      }

      final response = await http
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
                'maxOutputTokens': 4000,
              },
            }),
          )
          .timeout(
            const Duration(seconds: 45),
          );

      // ==========================================================
      // ERROR HANDLING
      // ==========================================================

      if (response.statusCode != 200) {
        try {
          final errorData = jsonDecode(response.body);

          final errorMessage =
              errorData['error']?['message'] ??
              'Unknown Gemini API error';

          return '''
❌ Gemini API Error

Status code: ${response.statusCode}

$errorMessage
''';
        } catch (_) {
          return '''
❌ Gemini API Error

Status code: ${response.statusCode}

Please check your Gemini API key and model configuration.
''';
        }
      }

      // ==========================================================
      // PARSE RESPONSE
      // ==========================================================

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        return '❌ Invalid response received from Gemini.';
      }

      final candidates = data['candidates'];

      if (candidates == null ||
          candidates is! List ||
          candidates.isEmpty) {
        return '''
❌ Gemini did not return a recipe.

Please try asking again.
''';
      }

      final firstCandidate = candidates.first;

      if (firstCandidate is! Map) {
        return '❌ Invalid Gemini response.';
      }

      final content = firstCandidate['content'];

      if (content == null || content is! Map) {
        return '❌ Gemini returned an empty response.';
      }

      final parts = content['parts'];

      if (parts == null ||
          parts is! List ||
          parts.isEmpty) {
        return '❌ Gemini returned an empty recipe.';
      }

      final buffer = StringBuffer();

      for (final part in parts) {
        if (part is Map && part['text'] != null) {
          buffer.write(part['text'].toString());
        }
      }

      final result = buffer.toString().trim();

      if (result.isEmpty) {
        return '❌ No recipe was generated.';
      }

      return result;
    } catch (e) {
      return '''
❌ Unable to connect to Chef AI.

Please check:
• Internet connection
• Gemini API key
• Gemini API access
• Gemini model availability

Error:
$e
''';
    }
  }
}