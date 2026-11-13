import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

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

  /// Vision fallback for the front of a pack: returns brand, product_name and
  /// category, or null when the service is unavailable (OCR result is kept).
  static Future<Map<String, String>?> identifyProduct(
    Uint8List imageBytes,
  ) async {
    try {
      // Phone photos are several MB; ~1024px JPEG keeps the upload fast.
      final jpeg = await Isolate.run(() {
        final decoded = img.decodeImage(imageBytes);
        if (decoded == null) return null;
        final oriented = img.bakeOrientation(decoded);
        final resized = oriented.width >= oriented.height
            ? (oriented.width > 1024
                ? img.copyResize(oriented, width: 1024)
                : oriented)
            : (oriented.height > 1024
                ? img.copyResize(oriented, height: 1024)
                : oriented);
        return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      });
      if (jpeg == null) return null;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/identify-product'),
      )
        ..headers.addAll({
          if (_appToken.isNotEmpty) 'X-App-Token': _appToken,
        })
        // No content type: the backend treats an untyped upload as JPEG.
        ..files.add(http.MultipartFile.fromBytes(
          'image',
          jpeg,
          filename: 'front.jpg',
        ));
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 60)),
      );
      if (response.statusCode != 200) {
        developer.log(
          'Product identification failed: HTTP ${response.statusCode}',
          name: 'RecipeAgentClient',
        );
        return null;
      }
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      return {
        'brand': body['brand']?.toString() ?? '',
        'product_name': body['product_name']?.toString() ?? '',
        'category': body['category']?.toString() ?? '',
      };
    } catch (error, stackTrace) {
      developer.log(
        'Product identification failed: ${error.runtimeType}: $error',
        name: 'RecipeAgentClient',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
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
