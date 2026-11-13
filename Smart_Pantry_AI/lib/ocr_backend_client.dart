import 'dart:async';
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
  static const String _timeoutSecondsRaw = String.fromEnvironment(
    'OCR_TIMEOUT_SECONDS',
    defaultValue: '180',
  );
  static final Duration requestTimeout = Duration(
    seconds: int.tryParse(_timeoutSecondsRaw) ?? 180,
  );

  static Future<OCRResult> recognize(
    File imageFile, {
    String mode = 'normal',
    String source = 'unknown',
  }) async {
    final stopwatch = Stopwatch()..start();
    final endpoint = Uri.parse('$backendUrl/ocr');
    debugPrint('OCR request: url=$endpoint mode=$mode source=$source');
    final imageSize = await imageFile.length();
    debugPrint(
      'OCR timing: request-start mode=$mode source=$source bytes=$imageSize',
    );

    final request = http.MultipartRequest(
      'POST',
      endpoint,
    )
      ..fields['mode'] = mode
      ..fields['source'] = source
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    late final http.StreamedResponse response;
    final requestStarted = Stopwatch()..start();
    try {
      response = await request.send().timeout(requestTimeout);
    } on SocketException catch (error) {
      debugPrint(
        'OCR connection failure: url=$endpoint mode=$mode '
        'error=${error.message} address=${error.address} port=${error.port}',
      );
      throw const OCRBackendException(
        'OCR server connection failed. Check that the phone can reach the backend and try again.',
      );
    } on TimeoutException {
      debugPrint(
        'OCR timeout: url=$endpoint mode=$mode '
        'timeoutSeconds=${requestTimeout.inSeconds}',
      );
      throw const OCRBackendException(
        'OCR is taking longer than expected. Retake the photo and try again.',
      );
    } on HttpException {
      rethrow;
    } catch (error) {
      debugPrint('OCR request failure: url=$endpoint mode=$mode error=$error');
      throw OCRBackendException('Could not reach the OCR server: $error');
    }
    debugPrint(
      'OCR timing: response mode=$mode status=${response.statusCode} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    late final String body;
    try {
      body = await response.stream.bytesToString().timeout(requestTimeout);
    } on TimeoutException {
      debugPrint(
        'OCR response timeout: url=$endpoint mode=$mode '
        'timeoutSeconds=${requestTimeout.inSeconds}',
      );
      throw const OCRBackendException(
        'OCR is taking longer than expected. Retake the photo and try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('OCR backend error: HTTP ${response.statusCode}');
      throw OCRBackendException(
        'OCR backend returned ${response.statusCode}. Retake the photo and try again.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const OCRBackendException(
        'OCR server returned an invalid response. Try again.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const OCRBackendException(
        'OCR server returned an invalid response. Try again.',
      );
    }

    final engine = decoded['engine'];
    if (engine is! String || engine != 'keras_ocr') {
      throw const OCRBackendException(
        'OCR server returned an unsupported engine response.',
      );
    }

    final text = decoded['text'];
    if (text is! String) {
      throw const OCRBackendException(
        'OCR server returned no readable text. Try again.',
      );
    }

    final detections = decoded['detections'];
    if (detections is! List) {
      throw const OCRBackendException(
        'OCR server returned an incomplete response. Try again.',
      );
    }

    final backendProcessingMs = (decoded['processing_ms'] as num?)?.toDouble();
    final requestElapsedMs = requestStarted.elapsedMilliseconds.toDouble();
    final uploadAndNetworkMs = backendProcessingMs == null
        ? null
        : (requestElapsedMs - backendProcessingMs)
            .clamp(0, double.infinity)
            .toDouble();
    final backendTimings = decoded['timing_ms'];
    debugPrint(
      'OCR timing: backend mode=$mode '
      'processingMs=$backendProcessingMs '
      'uploadAndNetworkMs=$uploadAndNetworkMs '
      'stages=$backendTimings',
    );
    debugPrint(
      'OCR timing: request-end mode=$mode textLength=${text.length} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return OCRResult(
      text: text.trim(),
      detections: detections,
      isEmpty: decoded['status'] == 'empty' || text.trim().isEmpty,
      source: decoded['source'] as String? ?? source,
      inputWidth: (decoded['input_size'] as Map?)?['width'] as int?,
      inputHeight: (decoded['input_size'] as Map?)?['height'] as int?,
      processingMs: backendProcessingMs,
      backendTimings: backendTimings is Map
          ? Map<String, dynamic>.from(backendTimings)
          : const <String, dynamic>{},
      requestElapsedMs: requestElapsedMs,
      uploadAndNetworkMs: uploadAndNetworkMs,
    );
  }
}

class OCRResult {
  final String text;
  final List<dynamic> detections;
  final bool isEmpty;
  final String source;
  final int? inputWidth;
  final int? inputHeight;
  final double? processingMs;
  final Map<String, dynamic> backendTimings;
  final double requestElapsedMs;
  final double? uploadAndNetworkMs;

  const OCRResult({
    required this.text,
    required this.detections,
    required this.isEmpty,
    required this.source,
    required this.inputWidth,
    required this.inputHeight,
    required this.processingMs,
    required this.backendTimings,
    required this.requestElapsedMs,
    required this.uploadAndNetworkMs,
  });
}

class OCRBackendException implements Exception {
  final String message;

  const OCRBackendException(this.message);

  @override
  String toString() => message;
}
