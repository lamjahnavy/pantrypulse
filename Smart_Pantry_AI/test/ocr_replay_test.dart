import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pantry_ai/ocr_service.dart';

Map<String, dynamic> _fixture(String name) => jsonDecode(
      File('test/fixtures/$name').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  // Real Keras-OCR output from a phone scan of a Britannia Marie Gold pack.
  test('Marie Gold back: slashes misread as 1 still give PKD and USE BY', () {
    final scan = _fixture('marie_gold_back_ocr.json');
    final result = OCRService.extractBackDetailsFromOCR(
      scan['text'] as String,
      scan['detections'] as List<dynamic>,
    );
    expect(result['mfd'], '07/10/2026');
    expect(result['exp'], '06/04/2027');
  });

  test('Marie Gold front: largest print becomes the product name', () {
    final scan = _fixture('marie_gold_front_ocr.json');
    final result = OCRService.extractFrontDetailsFromOCR(
      scan['text'] as String,
      scan['detections'] as List<dynamic>,
    );
    expect(result['name'], 'Marie Gold');
    expect(result['brand'], 'BRITANNIA');
    expect(result['category'], 'Snacks');
  });

  test('Vision fallback runs only when OCR is unsure and fills the gaps', () {
    final scan = _fixture('marie_gold_front_ocr.json');
    final confident = OCRService.extractFrontDetailsFromOCR(
      scan['text'] as String,
      scan['detections'] as List<dynamic>,
    );
    expect(OCRService.frontNeedsVisionFallback(confident), isFalse);

    final unsure = OCRService.extractFrontDetailsFromOCR('sn 10\nmincc', []);
    expect(OCRService.frontNeedsVisionFallback(unsure), isTrue);
    final merged = OCRService.mergeVisionDetails(unsure, {
      'brand': 'Britannia',
      'product_name': 'marie GOLD',
      'category': 'Snacks',
    });
    expect(merged['brand'], 'BRITANNIA');
    expect(merged['name'], 'Marie Gold');
    expect(merged['category'], 'Snacks');
  });
}
