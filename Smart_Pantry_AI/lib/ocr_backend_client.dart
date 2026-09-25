import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class OCRBackendClient {
  static const String backendUrl = String.fromEnvironment(
    'OCR_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static Future<String> recognize(
    File imageFile, {
    String mode = 'normal',
  }) async {
    final stopwatch = Stopwatch()..start();
    final endpoint = Uri.parse('$backendUrl/ocr');
    final imageSize = await imageFile.length();
    debugPrint('OCR timing: request-start mode=$mode bytes=$imageSize');

    final request = http.MultipartRequest(
      'POST',
      endpoint,
    )
      ..fields['mode'] = mode
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    final response = await request.send().timeout(
          const Duration(seconds: 45),
        );
    debugPrint(
      'OCR timing: response mode=$mode status=${response.statusCode} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('OCR backend error: HTTP ${response.statusCode}');
      throw HttpException(
        'OCR backend returned ${response.statusCode}: $body',
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid OCR backend response.');
    }

    final text = decoded['text'];
    if (text is! String) {
      throw const FormatException('OCR backend response has no text.');
    }

    debugPrint(
      'OCR timing: request-end mode=$mode textLength=${text.length} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return text.trim();
  }
}
