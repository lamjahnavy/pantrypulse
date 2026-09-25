import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_pantry_ai/gemini_service.dart';
import 'package:smart_pantry_ai/main.dart';
import 'package:smart_pantry_ai/ocr_service.dart';
import 'package:smart_pantry_ai/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pantry Pulse loads', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PantryPulseApp(cameras: []));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Pantry Pulse'), findsOneWidget);
  });

  test('OCR extracts numeric expiry and MFD dates', () {
    final result = OCRService.extractBackDetails(
      "PARLE\nMFD 03/02/2024\nBEST BEFORE 15/12/2025\nMRP Rs 5.00",
    );

    expect(result['mfd'], '03/02/2024');
    expect(result['exp'], '15/12/2025');
  });

  test('OCR extracts month-name expiry dates', () {
    final result = OCRService.extractBackDetails(
      "PARLE\nBEST BEFORE 10 OCT 2025\nMRP Rs 5.00",
    );

    expect(result['exp'], '10/10/2025');
  });

  test('OCR detects dates when the label uses manufacturing and expiry date wording', () {
    final result = OCRService.extractBackDetails(
      "Cookies\nNet Wt 250g\nManufacturing Date: 27/08/2024\nExpiry Date: 12/10/2026\nMRP Rs 75.00",
    );

    expect(result['mfd'], '27/08/2024');
    expect(result['exp'], '12/10/2026');
  });

  test('OCR falls back to multiple date tokens when labels are weak or missing', () {
    final result = OCRService.extractBackDetails(
      "Cookies\n27/08/2024\n12/10/2026\nNet Wt 250g",
    );

    expect(result['mfd'], '27/08/2024');
    expect(result['exp'], '12/10/2026');
  });

  test('OCR does not assign the same duplicate date to both MFD and EXP', () {
    final result = OCRService.extractBackDetails(
      "Cookies\n09/11/2025\n09/11/2025\nNet Wt 250g",
    );

    expect(result['mfd'], '09/11/2025');
    expect(result['exp'], 'Not detected');
  });

  test('OCR detects Indian FMCG labels with PKDDATE and BEST BEFORE X MONTHS', () {
    final result = OCRService.extractBackDetails(
      "PADMAVATHI SUPER MARKET\nAVAIL / MUSTARDS 250 GM\nPKDDATE: 24.Jul.2026\nBEST BEFORE 3 MONTHS\nSALE PRICE: 35.00\nMRP: 50.00",
    );

    expect(result['mfd'], '24/7/2026');
    expect(result['exp'], '24/10/2026');
    expect(result['price'], '35.00');
  });

  test('Gemini fallback recipe works without internet', () {
    final result = GeminiService.buildOfflineRecipe(
      'How can I make chicken curry?',
      pantryItems: ['onion', 'tomato', 'garlic'],
    );

    expect(result.toLowerCase(), contains('chicken curry'));
    expect(result.toLowerCase(), contains('ingredients'));
    expect(result.toLowerCase(), contains('onion'));
    expect(result.toLowerCase(), contains('cooking method'));
  });

  test('Recipe pantry availability excludes unrelated chicken curry items', () {
    final result = GeminiService.buildOfflineRecipe(
      'How can I make chicken curry?',
      pantryItems: ['chicken', 'onion', 'tomato', 'mustard seeds', 'sugar'],
    );

    expect(result.toLowerCase(), contains('chicken'));
    expect(result.toLowerCase(), contains('onion'));
    expect(result.toLowerCase(), isNot(contains('mustard seeds')));
    expect(result.toLowerCase(), isNot(contains('sugar')));
  });

  test('Meal planner persists locally when no user is signed in', () async {
    SharedPreferences.setMockInitialValues({});

    await StorageService.saveMealPlan({
      'Mon': 'Chicken Curry',
      'Tue': 'Dal Rice',
    });

    final loaded = await StorageService.loadMealPlan();
    expect(loaded['Mon'], 'Chicken Curry');
    expect(loaded['Tue'], 'Dal Rice');
  });

  test('OCR detects MFG dates and net quantity from snack pack labels', () {
    final result = OCRService.extractBackDetails(
      'MFG 27/09/25 18:19 30 g\nBB 27/01/26 20:19',
    );

    expect(result['mfd'], '27/09/2025');
    expect(result['quantity'], '30 g');
  });

  test('OCR picks product name and brand from Indian snack packaging', () {
    final result = OCRService.extractFrontDetails(
      'LAYS\nCream & Onion\nNet Wt 30 g',
    );

    expect(result['brand'], 'LAYS');
    expect(result['name'], contains('Cream'));
  });

  test('OCR handles month-year dates and duration units', () {
    final result = OCRService.extractBackDetails(
      'MFO 08/2026\nBEST BEF0RE 12 MONTHS\nNET CONTENT 1 litre',
    );

    expect(result['mfd'], '1/8/2026');
    expect(result['exp'], '01/08/2027');
    expect(result['quantity'], '1 l');
  });

  test('OCR handles noisy expiry labels and spelled-out quantities', () {
    final result = OCRService.extractBackDetails(
      'MFC DATE 12-08-26\nEYP DATE 11-08-27\nNET WEIGHT 250 grams',
    );

    expect(result['mfd'], '12/08/2026');
    expect(result['exp'], '11/08/2027');
    expect(result['quantity'], '250 g');
  });

  test('OCR handles package dates with month names and two-digit years', () {
    final result = OCRService.extractBackDetails(
      'MFD: 17 AUG 26\nUSE BY: 13 JAN 27\nMRP: Rs. 5.00',
    );

    expect(result['mfd'], '17/8/2026');
    expect(result['exp'], '13/1/2027');
  });

  test('OCR handles dotted day-month-year package dates', () {
    final result = OCRService.extractBackDetails(
      'MFD 16.08.26\nEXP 13.01.27\nMRP Rs 10.00',
    );

    expect(result['mfd'], '16/08/2026');
    expect(result['exp'], '13/01/2027');
  });

  test('OCR handles punctuation and spacing noise in date labels', () {
    final result = OCRService.extractBackDetails(
      'MFG. DATE: 16.08.26\nUSEBY: 13.01.27\nMRP: Rs. 10.00',
    );

    expect(result['mfd'], '16/08/2026');
    expect(result['exp'], '13/01/2027');
  });

  test('OCR rejects impossible dates and distinguishes MRP from quantity', () {
    final result = OCRService.extractBackDetails(
      'MFD 35/19/2026\nMRP Rs. 120\nNET WT 500 g\nBATCH 12345',
    );

    expect(result['mfd'], 'Not detected');
    expect(result['price'], '120.00');
    expect(result['quantity'], '500 g');
  });

  test('OCR fixes common numeric OCR issues in date strings', () {
    final result = OCRService.extractBackDetails(
      'MFG 16.O8.2G\nEXP 13-01-2?\nMRP Rs 10.00',
    );

    expect(result['mfd'], '16/08/2026');
    expect(result['exp'], '13/01/2027');
  });

  test('OCR reads Indian pricing and quantity strings with symbols and spacing noise', () {
    final result = OCRService.extractBackDetails(
      'MRP ₹50\nNET WT 500g\n1kg pack\nPRICE 45.00',
    );

    expect(result['price'], '50.00');
    expect(result['quantity'], '500 g');
  });

  test('OCR handles mixed date label variants and month names', () {
    final result = OCRService.extractBackDetails(
      'PKD DATE 24.Jul.2026\nUSE BY 13 JAN 27\nMRP: ₹ 65',
    );

    expect(result['mfd'], '24/7/2026');
    expect(result['exp'], '13/1/2027');
    expect(result['price'], '65.00');
  });

  test('OCR supports required Indian date formats and spacing noise', () {
    final samples = [
      'MFD 10/10/2026',
      'MFD 10/10/26',
      'MFD 10-10-2026',
      'MFD 10.10.2026',
      'MFD 10 OCT 2026',
      'MFD 10-OCT-2026',
      'MFD OCT 2026',
      'MFD OCT-26',
      'MFD 10/2026',
      'MFD 10 10 26',
      'MFD 10 OCT 26',
      'MFD 10 10 2026',
    ];

    for (final sample in samples) {
      final result = OCRService.extractBackDetails(sample);
      expect(result['mfd'], isNot('Not detected'), reason: sample);
    }
  });

  test('OCR recognizes month-only labels and relative shelf-life phrases', () {
    final result = OCRService.extractBackDetails(
      'MFD 10/01/2026\nBEST BEFORE 6 MONTHS FROM MFD',
    );

    expect(result['mfd'], '10/01/2026');
    expect(result['exp'], '10/07/2026');

    final monthOnly = OCRService.extractBackDetails('MFD OCT-26');
    expect(monthOnly['mfd'], '1/10/2026');
  });

  test('OCR corrects common OCR confusion only in date tokens', () {
    final result = OCRService.extractBackDetails(
      'MFD 16.O8.2G\nEXP 13-01-2?\nBEF0RE 17/10/27\nMFO 0CT 2026\nMRP Rs 10.00',
    );

    expect(result['mfd'], '16/08/2026');
    expect(result['exp'], '13/01/2027');
    expect(result['mfd'], isNot(contains('O')));
  });

  test('OCR rejects impossible dates and preserves ambiguous ones for review', () {
    final impossible = OCRService.extractBackDetails('MFD 45/19/2026\nEXPIRE 99/99/99');
    expect(impossible['mfd'], 'Not detected');
    expect(impossible['exp'], 'Not detected');

    final ambiguous = OCRService.extractBackDetails('MFD 13-01-2?');
    expect(ambiguous['mfd'], '13/01/2027');
  });

  test('OCR resolves relative shelf-life dates from MFD', () {
    final result = OCRService.extractBackDetails(
      'MFD 10/01/2026\nBEST BEFORE 6 MONTHS FROM MFD',
    );

    expect(result['mfd'], '10/01/2026');
    expect(result['exp'], '10/07/2026');
  });

  test('OCR separates batch codes from dates', () {
    final result = OCRService.extractBackDetails(
      'B.No A6G721\nMFD 10/08/26\nMRP 120',
    );

    expect(result['mfd'], '10/08/2026');
    expect(result['price'], '120.00');
  });
}
