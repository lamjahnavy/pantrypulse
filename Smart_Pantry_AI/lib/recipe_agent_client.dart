import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'product_model.dart';

class RecipeAgentException implements Exception {
  final String message;

  const RecipeAgentException(this.message);

  @override
  String toString() => message;
}

class RecipeAgentClient {
  static const String baseUrl = String.fromEnvironment(
    'RECIPE_AGENT_URL',
    defaultValue: 'http://127.0.0.1:8001',
  );
  static const int _timeoutSeconds = int.fromEnvironment(
    'RECIPE_AGENT_TIMEOUT_SECONDS',
    defaultValue: 95,
  );
  static const Duration timeout = Duration(seconds: _timeoutSeconds);
  // Shared secret for a hosted backend; empty for a local one.
  static const String _appToken = String.fromEnvironment('RECIPE_AGENT_TOKEN');

  static Future<Map<String, dynamic>> chat({
    required String message,
    required List<Product> pantry,
    required String context,
    required bool pantryCooking,
  }) async {
    final endpoint = pantryCooking ? '/pantry-cook' : '/chat';
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${message.hashCode}';
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'X-Request-ID': requestId,
              if (_appToken.isNotEmpty) 'X-App-Token': _appToken,
            },
            body: jsonEncode({
              'message': message,
              'pantry': pantry.map(_snapshot).toList(),
              'context': context.trim().isEmpty
                  ? const []
                  : [
                      {'role': 'assistant', 'content': context},
                    ],
            }),
          )
          .timeout(timeout);

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } on FormatException {
        throw const RecipeAgentException(
          'Recipe Agent returned malformed data.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RecipeAgentException(
          body['message']?.toString() ?? 'Recipe Agent request failed.',
        );
      }
      return body;
    } on TimeoutException catch (error, stackTrace) {
      developer.log(
        'Recipe Agent timeout after ${timeout.inSeconds}s: $error',
        name: 'RecipeAgentClient',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Recipe Agent request failed: ${error.runtimeType}: $error',
        name: 'RecipeAgentClient',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static Map<String, String> _snapshot(Product product) {
    return {
      'id': product.id,
      'name': product.name,
      'quantity': product.quantity,
      'exp': product.exp,
      'status': product.status,
      'brand': product.brand,
      'category': product.category,
    };
  }
}
