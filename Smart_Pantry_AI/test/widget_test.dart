import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_pantry_ai/gemini_service.dart';
import 'package:smart_pantry_ai/main.dart';
import 'package:smart_pantry_ai/ocr_service.dart';
import 'package:smart_pantry_ai/ocr_roi.dart';
import 'package:smart_pantry_ai/storage_service.dart';
import 'dart:io';

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

  test(
      'OCR detects dates when the label uses manufacturing and expiry date wording',
      () {
    final result = OCRService.extractBackDetails(
      "Cookies\nNet Wt 250g\nManufacturing Date: 27/08/2024\nExpiry Date: 12/10/2026\nMRP Rs 75.00",
    );

    expect(result['mfd'], '27/08/2024');
    expect(result['exp'], '12/10/2026');
  });

  test('OCR falls back to multiple date tokens when labels are weak or missing',
      () {
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

  test('OCR detects Indian FMCG labels with PKDDATE and BEST BEFORE X MONTHS',
      () {
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

  test('OCR handles undelimited dates returned by recognizers', () {
    final result = OCRService.extractBackDetails(
      'MFD 01092026\nEXP 31082027\nMRP Rs 134.00',
    );

    expect(result['mfd'], '01/09/2026');
    expect(result['exp'], '31/08/2027');
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

  test(
      'OCR reads Indian pricing and quantity strings with symbols and spacing noise',
      () {
    final result = OCRService.extractBackDetails(
      'MRP ₹50\nNET WT 500g\n1kg pack\nPRICE 45.00',
    );

    expect(result['price'], '50.00');
    expect(result['quantity'], '500 g');
  });

  test('OCR separates net quantity and MRP from unit price', () {
    final result = OCRService.extractBackDetails(
      'NET QUANTITY: 500 g\nMRP: ₹134.00\nUNIT PRICE: ₹0.27 per g\nBATCH KVQ0010926',
    );

    expect(result['quantity'], '500 g');
    expect(result['price'], '134.00');
  });

  test('OCR does not use a unit price as quantity or MRP', () {
    final result = OCRService.extractBackDetails(
      '₹0.27 per g\nBATCH KVQ0010926',
    );

    expect(result['quantity'], 'Not detected');
    expect(result['price'], '0.00');
  });

  test('temporary OCR file remains until the lease is disposed', () async {
    final directory = await Directory.systemTemp.createTemp('pantry_ocr_test_');
    final file = File('${directory.path}${Platform.pathSeparator}roi.jpg');
    await file.writeAsBytes([1, 2, 3]);
    final lease = OCRTemporaryFileLease(file.path);

    expect(await file.exists(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(await file.exists(), isTrue);

    await lease.dispose();
    expect(await file.exists(), isFalse);
    await directory.delete();
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

  test('OCR rejects impossible dates and preserves ambiguous ones for review',
      () {
    final impossible =
        OCRService.extractBackDetails('MFD 45/19/2026\nEXPIRE 99/99/99');
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

  test('OCR date parser covers the supported label and format matrix', () {
    final samples = <String>[
      'MFD 12/05/2025',
      'MFG 12-05-2025',
      'PKD 12.05.2025',
      'MFD 12/05/25',
      'MFG 05/2025',
      'MFD 05-2025',
      'MFD 05/25',
      'MFD 12052025',
      'MFD 12 05 2025',
      'MFD 12 MAY 2025',
      'MFD MAY 2025',
      'MFD May-25',
      'MFD 12MAY25',
      'MANUFACTURED 12/05/2025',
      'MANUFACTURING DATE 12-05-2025',
      'MFD.DATE 12.05.2025',
      'MFG.DATE 12/05/2025',
      'PACKED ON 12/05/2025',
      'PACKAGING DATE 12/05/2025',
      'DATE OF PACKING 12/05/2025',
      'DOM 12/05/2025',
      'EXPIRY DATE 12/05/2025',
      'EXPIRES 12/05/2025',
      'USE BY 12/05/2025',
      'BEST BEFORE 12/05/2025',
      'BB 12/05/2025',
      'BESTBEFORE 12/05/2025',
      'MFD 12.O5.2O25',
      'MFD 12 05 25',
      'MFD\n12/05/2025',
      'MFD\n12-05-2025',
      'MFD\n12.05.2025',
      'MFD\n12052025',
      'MFD 01/01/2025',
      'MFD 02-02-2025',
      'MFD 03.03.2025',
      'MFD 04/2025',
    ];

    for (final sample in samples) {
      final result = OCRService.extractBackDetails(sample);
      final field = RegExp(
        r'\b(EXP|EXPIRY|EXPIRES|USE\s*BY|BEST\s*BEFORE|BB)\b',
        caseSensitive: false,
      ).hasMatch(sample)
          ? 'exp'
          : 'mfd';
      expect(
        result[field],
        isNot('Not detected'),
        reason: sample,
      );
    }
  });

  test('OCR associates two-column labels with right-column values', () {
    const rawText = '''
Batch Code
KVQO010926
MFD.
01/09/2026
USE BY
31/08/2027
MRP Rs
134.00
USP Rs
(USP : Rs. 0.27 per g)
Net Quantity
500 g
''';
    List<List<double>> box(
            double left, double top, double right, double bottom) =>
        [
          [left, top],
          [right, top],
          [right, bottom],
          [left, bottom],
        ];

    final detections = <Map<String, dynamic>>[
      {'text': 'MFD.', 'box': box(20, 100, 70, 120)},
      {'text': '01/09/2026', 'box': box(160, 112, 280, 132)},
      {'text': 'USE BY', 'box': box(20, 150, 90, 170)},
      {'text': '31/08/2027', 'box': box(160, 162, 280, 182)},
      {'text': 'MRP Rs', 'box': box(20, 200, 100, 220)},
      {'text': '134.00', 'box': box(160, 212, 230, 232)},
      {'text': 'USP Rs', 'box': box(20, 250, 100, 270)},
      {'text': '0.27 per g', 'box': box(160, 262, 250, 282)},
      {'text': 'NET QUANTITY', 'box': box(20, 300, 140, 320)},
      {'text': '500 g', 'box': box(160, 312, 220, 332)},
    ];

    final result = OCRService.extractBackDetailsFromOCR(rawText, detections);

    expect(result['mfd'], '01/09/2026');
    expect(result['exp'], '31/08/2027');
    expect(result['price'], '134.00');
    expect(result['quantity'], '500 g');
  });

  test('OCR prefers decimal MRP over fragmented noise from a real pack', () {
    const rawText = '''
net weight 5k9 59
mrp k 285100 285.0
pkde 2A09 1501102a 15/02/2024
best 8EU before 8EE E aomies 14/01/202
''';

    final result = OCRService.extractBackDetails(rawText);

    expect(result['quantity'], '5 kg');
    expect(result['price'], '285.00');
    expect(result['mfd'], '15/02/2024');
    expect(result['exp'], 'Not detected');
  });

  test('OCR binds fuzzy split labels from the saved real backend response', () {
    List<List<double>> box(
            double left, double top, double right, double bottom) =>
        [
          [left, top],
          [right, top],
          [right, bottom],
          [left, bottom],
        ];

    const rawText =
        'pkds 2/09 1010812024 10/08/2024\nuse J9E by 81 1070812026 10/08/2026';
    final detections = <Map<String, dynamic>>[
      {'text': 'pkds', 'box': box(363, 1804, 587, 1922)},
      {'text': '1010812024', 'box': box(644, 1804, 1202, 1925)},
      {'text': '10/08/2024', 'box': box(644, 1804, 1202, 1925)},
      {'text': 'use', 'box': box(367, 1983, 532, 2107)},
      {'text': 'by', 'box': box(551, 1986, 698, 2107)},
      {'text': '1070812026', 'box': box(735, 1983, 1286, 2112)},
      {'text': '10/08/2026', 'box': box(735, 1983, 1286, 2112)},
    ];

    final result = OCRService.extractBackDetailsFromOCR(rawText, detections);

    expect(result['mfd'], '10/08/2024');
    expect(result['exp'], '10/08/2026');
  });

  test('OCR fuzzy date labels do not promote unrelated numeric strings', () {
    const rawText = '''
Batch 15072024
MRP 285.00
Phone 9876543210
PKD 15/07/2024
EXP 14/01/2025
''';

    final result = OCRService.extractBackDetails(rawText);

    expect(result['mfd'], '15/07/2024');
    expect(result['exp'], '14/01/2025');
    expect(result['price'], '285.00');
    expect(result['exp'], isNot('9876543210'));
  });

  test('OCR repairs uncertain one-character quantity tokens by box position',
      () {
    List<List<double>> box(
            double left, double top, double right, double bottom) =>
        [
          [left, top],
          [right, top],
          [right, bottom],
          [left, bottom],
        ];

    const rawText = 'net wegnl weight i kg';
    final detections = <Map<String, dynamic>>[
      {'text': 'net', 'box': box(357, 982, 497, 1087)},
      {'text': 'wegnl', 'box': box(514, 981, 788, 1105)},
      {'text': 'weight', 'box': box(516, 1269, 835, 1409)},
      {'text': 'i', 'box': box(944, 1336, 1054, 1409)},
      {'text': 'kg', 'box': box(1007, 1275, 1112, 1409)},
    ];

    final result = OCRService.extractBackDetailsFromOCR(rawText, detections);

    expect(result['quantity'], '1 kg');
    expect(result['quantity_status'], 'UNCERTAIN');
  });

  test('OCR keeps existing 5 kg quantity behavior', () {
    final result = OCRService.extractBackDetails('Net Wt 5 kg');

    expect(result['quantity'], '5 kg');
    expect(result['quantity_status'], 'CERTAIN');
  });

  test('OCR does not repair a lone i, ingredient text, or batch number', () {
    expect(OCRService.extractBackDetails('ingredient i')['quantity'],
        'Not detected');
    expect(OCRService.extractBackDetails('Batch i 123456')['quantity'],
        'Not detected');
    final loneToken = OCRService.extractBackDetails('i');
    expect(loneToken['quantity'], 'Not detected');
  });

  test('OCR splits MFD and EXP that share one line', () {
    const cases = <String, List<String>>{
      'MFD: 12/03/2025 EXP: 11/09/2026': ['12/03/2025', '11/09/2026'],
      'Mfg.Date:01/05/25 Exp.Date:01/11/25': ['01/05/2025', '01/11/2025'],
      'PKD 05/24 EXP 11/24': ['1/5/2024', '30/11/2024'],
      'MFD:JAN 2025 EXP:DEC 2025': ['1/1/2025', '31/12/2025'],
    };
    cases.forEach((text, expected) {
      final result = OCRService.extractBackDetails(text);
      expect([result['mfd'], result['exp']], expected, reason: text);
    });
  });

  test('OCR reads glued, year-first and US-style dates', () {
    const cases = <String, List<String>>{
      'MFG 13NOV2025\nEXP 12MAY26': ['13/11/2025', '12/5/2026'],
      'MFD 2025-11-13\nEXP 2026-05-12': ['13/11/2025', '12/5/2026'],
      'MFD 11/05/2025\nEXP 11/25/2026': ['11/05/2025', '25/11/2026'],
    };
    cases.forEach((text, expected) {
      final result = OCRService.extractBackDetails(text);
      expect([result['mfd'], result['exp']], expected, reason: text);
    });
  });

  test('OCR resolves shelf-life phrases in any line order', () {
    const cases = <String, List<String>>{
      'BEST BEFORE 6 MONTHS FROM MFG\nMFD 01/05/2025': [
        '01/05/2025',
        '01/11/2025',
      ],
      'USE WITHIN 9 MONTHS FROM MANUFACTURE\nPKD 01/05/2025': [
        '01/05/2025',
        '01/02/2026',
      ],
      'SHELF LIFE: 12 MONTHS\nMFD 01/05/2025': ['01/05/2025', '01/05/2026'],
      'Date of Packaging 03/2025\nBest Before 18 months from packaging': [
        '1/3/2025',
        '01/09/2026',
      ],
    };
    cases.forEach((text, expected) {
      final result = OCRService.extractBackDetails(text);
      expect([result['mfd'], result['exp']], expected, reason: text);
    });
  });

  test('OCR ignores company and look-alike words as date labels', () {
    for (final text in [
      'Packed by: XYZ Foods Pvt Ltd\nEXP 10/10/2026',
      'Manufactured in: Kingdom of Spain\nEXP 10/10/2026',
    ]) {
      final result = OCRService.extractBackDetails(text);
      expect(result['mfd'], 'Not detected', reason: text);
      expect(result['exp'], '10/10/2026', reason: text);
    }
  });

  test('OCR finds brands despite apostrophes, OCR slips and slogans', () {
    const cases = <String, List<String>>{
      "Lay's\nAmerican Style Cream & Onion": [
        'LAYS',
        'American Style Cream Onion',
      ],
      'BRlTANNIA\nMarie Gold': ['BRITANNIA', 'Marie Gold'],
      'AMUI\nPasteurised Butter': ['AMUL', 'Pasteurised Butter'],
      'Bingo!\nMad Angles\nAchaari Masti': ['BINGO', 'Mad Angles'],
      'NEW\nKissan\nFresh Tomato Ketchup': ['KISSAN', 'Fresh Tomato Ketchup'],
      'Rich in Protein\nPATANJALI\nDoodh Biscuit': [
        'PATANJALI',
        'Doodh Biscuit',
      ],
    };
    cases.forEach((text, expected) {
      final result = OCRService.extractFrontDetails(text);
      expect([result['brand'], result['name']], expected, reason: text);
    });
  });
}
