import '../recipe_service.dart';

/// Compatibility facade for older recipe-agent callers.
///
/// Gemini credentials and tool execution are owned by the Python Recipe Agent.
class GeminiService {
  static Future<String> generateRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) {
    return RecipeService.generateRecipe(
      userQuestion,
      pantryItems: pantryItems,
    );
  }

  static Future<Map<String, dynamic>> generateWithTools({
    required String systemInstruction,
    required String userPrompt,
    required List<Map<String, dynamic>> tools,
  }) async {
    return {
      'success': false,
      'error':
          'Tool execution is available only through the Python Recipe Agent.',
    };
  }
}
