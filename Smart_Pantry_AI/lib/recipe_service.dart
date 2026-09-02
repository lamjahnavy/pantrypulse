import 'gemini_service.dart';

class RecipeService {
  static Future<String> generateRecipe(
    String userQuestion,
  ) async {
    final question = userQuestion.trim();

    if (question.isEmpty) {
      return 'Please enter the recipe you want to make.';
    }

    return await GeminiService.generateRecipe(question);
  }
}