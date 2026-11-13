import 'dart:developer' as developer;

import 'recipe_agent_client.dart';
import 'gemini_service.dart';
import 'product_model.dart';

class RecipeService {
  static Future<String> generateRecipe(
    String userQuestion, {
    List<String> pantryItems = const [],
  }) async {
    final products =
        pantryItems.map((item) => _productFromDisplayValue(item)).toList();
    return generateRecipeForProducts(
      userQuestion,
      pantry: products,
    );
  }

  static Future<String> generateRecipeForProducts(
    String userQuestion, {
    List<Product> pantry = const [],
    String conversationContext = '',
  }) async {
    final question = userQuestion.trim();
    if (question.isEmpty) {
      return 'Please enter the recipe you want to make.';
    }

    try {
      final response = await RecipeAgentClient.chat(
        message: question,
        pantry: pantry,
        context: conversationContext,
        pantryCooking: false,
      );
      return GeminiService.formatAgentResponse(response);
    } on RecipeAgentException catch (error, stackTrace) {
      developer.log(
        'Online Recipe Agent returned an error: $error',
        name: 'RecipeService',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Online Recipe Agent request failed: $error',
        name: 'RecipeService',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static Future<String> generatePantryCooking({
    required List<Product> pantry,
    String userRequest = '',
  }) async {
    final question = userRequest.trim().isEmpty
        ? 'Suggest a suitable recipe using products nearing expiry.'
        : userRequest;
    try {
      final response = await RecipeAgentClient.chat(
        message: question,
        pantry: pantry,
        context: 'Pantry Cooking mode.',
        pantryCooking: true,
      );
      return GeminiService.formatAgentResponse(response);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Pantry Cooking online Agent request failed: $error',
        name: 'RecipeService',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static Product _productFromDisplayValue(String value) {
    final match = RegExp(r'^(.+?)\s*\(([^()]*)\)\s*$').firstMatch(value.trim());
    return Product(
      id: value,
      name: match?.group(1)?.trim() ?? value.trim(),
      quantity: match?.group(2)?.trim() ?? 'Not detected',
      addedDate: DateTime.now(),
    );
  }
}
