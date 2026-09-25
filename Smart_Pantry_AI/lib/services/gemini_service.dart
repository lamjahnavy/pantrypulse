import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const String model = 'gemini-3.6-flash';
  static const String endpoint = 'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<Map<String, dynamic>> generateWithTools({
    required String systemInstruction,
    required String userPrompt,
    required List<Map<String, dynamic>> tools,
  }) async {
    if (apiKey.trim().isEmpty) {
      return {
        'success': false,
        'error': 'Gemini API key is not configured. Provide --dart-define=GEMINI_API_KEY=YOUR_KEY',
      };
    }

    final url = Uri.parse('$endpoint/$model:generateContent?key=$apiKey');

    final requestBody = {
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt},
          ],
        },
      ],
      'tools': [
        {
          'functionDeclarations': tools,
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 3000,
      },
    };

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        return {
          'success': false,
          'error': body['error']?['message'] ?? 'Gemini API request failed.',
        };
      }

      final decoded = jsonDecode(response.body);
      final candidates = decoded['candidates'] as List? ?? const [];

      if (candidates.isEmpty) {
        return {
          'success': false,
          'error': 'Gemini returned no candidate output.',
        };
      }

      final first = candidates.first as Map<String, dynamic>;
      final content = first['content'] as Map<String, dynamic>? ?? const {};
      final parts = content['parts'] as List? ?? const [];

      final text = StringBuffer();
      final functionCalls = <Map<String, dynamic>>[];

      for (final part in parts) {
        final map = part as Map<String, dynamic>;

        if (map.containsKey('text')) {
          text.write(map['text']);
        }

        if (map.containsKey('functionCall')) {
          functionCalls.add(map['functionCall'] as Map<String, dynamic>);
        }
      }

      return {
        'success': true,
        'text': text.toString().trim(),
        'functionCalls': functionCalls,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Communication failure while calling Gemini: $e',
      };
    }
  }

  static Future<String> generateRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) async {
    final question = userQuestion.trim();
    if (question.isEmpty) {
      return 'Please enter the recipe you want to make.';
    }

    final pantryText = pantryItems.isEmpty
        ? 'No pantry information available.'
        : pantryItems.join(', ');

    final prompt = '''
You are Chef AI, an expert Indian and international cooking assistant.

User request:
$userQuestion

Pantry information:
$pantryText

Respect the user request exactly and do not replace it with a different dish.
Provide a complete recipe with ingredients, available pantry items, missing items, and step-by-step cooking method.
''';

    final systemInstruction = '''
You are an expert Recipe Assistant.
You must never replace a requested dish with a different dish.
Use pantry items only as a supplementary availability check.
Always produce practical cooking instructions.
''';

    final tools = <Map<String, dynamic>>[];

    final result = await generateWithTools(
      systemInstruction: systemInstruction,
      userPrompt: prompt,
      tools: tools,
    );

    if (result['success'] == false) {
      return result['error'] as String? ?? 'Recipe generation failed.';
    }

    return (result['text'] as String).isNotEmpty
        ? result['text'] as String
        : 'No recipe generated.';
  }
}
