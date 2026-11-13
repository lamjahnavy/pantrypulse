import 'dart:math' as math;

import 'ocr_box.dart';

class OCRService {
  static const _knownBrands = <String>[
    'PARLE AGRO',
    'MOTHER DAIRY',
    'SURF EXCEL',
    'AASHIRVAAD',
    'BRITANNIA',
    'HALDIRAM',
    'KURKURE',
    'KELLOGGS',
    'COLGATE',
    'PEPSODENT',
    'HORLICKS',
    'BOURNVITA',
    'NESTLE',
    'MAGGI',
    'AMUL',
    'TATA',
    'DABUR',
    'PARLE',
    'ITC',
    'CADBURY',
    'PANTENE',
    'DOVE',
    'ARIEL',
    'EVEREST',
    'FORTUNE',
    'SAFFOLA',
    'PEPSI',
    'COKE',
    'LAYS',
    'NANDINI',
    'HERITAGE',
    'AACHI',
    'PRIYA',
    'MDH',
    'MTR',
    'MARICO',
    'P&G',
    'HUL',
    'RED LABEL',
    'BROOKE BOND',
    'SUNFEAST',
    'MONACO',
    'GOOD DAY',
    'OREO',
    'FROOTI',
    'THUMS UP',
    'COCA COLA',
    'TIGER',
    'BINGO',
    'PATANJALI',
    'KISSAN',
    'KNORR',
    'CHINGS',
    'YIPPEE',
    'TOP RAMEN',
    'WAI WAI',
    'BIKAJI',
    'BIKANERVALA',
    'BALAJI',
    'UNCLE CHIPPS',
    'PRINGLES',
    'DORITOS',
    'CHEETOS',
    'UNIBIC',
    'PRIYAGOLD',
    'ANMOL',
    'CREMICA',
    'MCVITIES',
    'FERRERO',
    'KINDER',
    'NUTELLA',
    'HERSHEYS',
    'SNICKERS',
    'KITKAT',
    'DAIRY MILK',
    'MILKYBAR',
    'MENTOS',
    'ALPENLIEBE',
    'BRU',
    'NESCAFE',
    'TAJ MAHAL',
    'WAGH BAKRI',
    'TETLEY',
    'LIPTON',
    'TATA TEA',
    'TATA SAMPANN',
    'CATCH',
    'BADSHAH',
    'SAKTHI',
    'EASTERN',
    'GITS',
    'MOTHERS RECIPE',
    'NILONS',
    'CHITALE',
    'DAAWAT',
    'INDIA GATE',
    'KOHINOOR',
    'LAL QILLA',
    'PILLSBURY',
    'ANNAPURNA',
    'SHAKTI BHOG',
    'RAJDHANI',
    'BAGRRYS',
    'QUAKER',
    'SUNDROP',
    'DHARA',
    'GEMINI',
    'EMAMI',
    'GOWARDHAN',
    'MILKY MIST',
    'AAVIN',
    'MILMA',
    'VERKA',
    'GOKUL',
    'EPIGAMIA',
    'AKSHAYAKALPA',
    'HATSUN',
    'AROKYA',
    'DODLA',
    'JERSEY',
    'KWALITY WALLS',
    'HAVMOR',
    'VADILAL',
    'CREAMBELL',
    'SPRITE',
    'FANTA',
    'LIMCA',
    'MAAZA',
    'MIRINDA',
    '7UP',
    'MOUNTAIN DEW',
    'STING',
    'RED BULL',
    'BISLERI',
    'KINLEY',
    'AQUAFINA',
    'PAPER BOAT',
    'TROPICANA',
    'RASNA',
    'TANG',
    'GLUCON D',
    'COMPLAN',
    'PROTINEX',
    'ROOH AFZA',
    'HAMDARD',
    'BAIDYANATH',
    'ORGANIC INDIA',
    '24 MANTRA',
    'SAFAL',
    'VEEBA',
    'FUNFOODS',
    'DR OETKER',
    'HELLMANNS',
    'KRAFT',
    'DEL MONTE',
    'HIMALAYA',
    'DETTOL',
    'LIFEBUOY',
    'LUX',
    'VIM',
    'RIN',
    'TIDE',
    'NIRMA',
    'GHADI',
    'HARPIC',
    'LIZOL',
    'PARACHUTE',
    'CLINIC PLUS',
    'CLOSE UP',
    'SENSODYNE',
    'GODREJ',
    'ID FRESH',
    'MOTHER DAIRY',
  ];

  // Letters OCR commonly confuses (I/l/1, O/0, S/5, B/8), folded to one form.
  static String _ocrFold(String value) => value
      .replaceAll(RegExp(r'[L1|]'), 'I')
      .replaceAll('0', 'O')
      .replaceAll('5', 'S')
      .replaceAll('8', 'B');

  static bool _brandTokenMatch(String token, String brandToken) {
    if (token == brandToken || token == '${brandToken}S') return true;
    if (_ocrFold(token) == _ocrFold(brandToken)) return true;
    // One wrong letter is only safe on longer words ("BRITANIA").
    return brandToken.length >= 6 && _fuzzyLabelMatch(token, brandToken);
  }

  // Matches known brands tolerating OCR slips and apostrophes (LAY'S, AMUI).
  static String? _matchBrand(String line) {
    final tokens = line
        .toUpperCase()
        .replaceAll(RegExp("['’`]"), '')
        .split(RegExp(r'[^A-Z0-9&|]+'))
        .where((token) => token.isNotEmpty)
        .toList();
    String? best;
    for (final brand in _knownBrands) {
      final brandTokens = brand.split(' ');
      for (var start = 0;
          start + brandTokens.length <= tokens.length;
          start++) {
        var matches = true;
        for (var i = 0; i < brandTokens.length; i++) {
          if (!_brandTokenMatch(tokens[start + i], brandTokens[i])) {
            matches = false;
            break;
          }
        }
        if (matches && (best == null || brand.length > best.length)) {
          best = brand;
        }
      }
    }
    return best;
  }

  // Pack slogans that are never the product name.
  static bool _isMarketingNoise(String line) {
    return RegExp(
      r'^(?:NEW|NOW|NEW PACK|BIG PACK|VALUE PACK|FAMILY PACK|COMBO|OFFER|'
      r'FREE|SAVE\b.*|EXTRA\b.*|\d+\s*%.*|RICH IN\b.*|HIGH IN\b.*|'
      r'SOURCE OF\b.*|NO ADDED\b.*|ZERO\b.*|LIMITED EDITION|VEG|NON VEG|'
      r'VEGETARIAN|PURE VEG|TRANS FAT FREE|FSSAI\b.*|LIC\b.*|TM|R)$',
      caseSensitive: false,
    ).hasMatch(line.trim());
  }

  static const _productKeywords = <String>[
    'MILK',
    'CURD',
    'PANEER',
    'BUTTER',
    'CHEESE',
    'GHEE',
    'ATTA',
    'RICE',
    'DAL',
    'PULSE',
    'SALT',
    'SUGAR',
    'OIL',
    'COFFEE',
    'TEA',
    'JUICE',
    'SODA',
    'CHIPS',
    'BISCUIT',
    'COOKIE',
    'JAM',
    'KETCHUP',
    'SAUCE',
    'NOODLE',
    'PASTA',
    'WHEAT',
    'FLOUR',
    'CEREAL',
    'OATS',
    'SPICE',
    'MASALA',
    'SNACK',
    'CHOCOLATE',
    'SOAP',
    'SHAMPOO',
    'DETERGENT',
    'CLEANER',
    'BIRYANI',
    'CHICKEN',
    'TURMERIC',
    'BASMATI',
    'NIMKI',
  ];
  // ============================================================
  // FRONT SIDE
  // Product Name + Brand + Category
  // ============================================================

  static Map<String, String> extractFrontDetails(String text) {
    String name = 'Unknown Product';
    String brand = 'Unknown Brand';

    final normalizedText = _normalizeText(text);

    final lines = normalizedText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final validLines = _removeNoise(lines)
        .where((line) => !_isMarketingNoise(_cleanup(line)))
        .toList();

    final frontProductKeywords = [
      'CREAM',
      'ONION',
      'CLASSIC',
      'MASALA',
      'CHILLI',
      'SALT',
      'NIMK',
      'CHEESE',
      'POTATO',
      'CHIPS',
      'CRISPS',
      'FRIES',
      'WAFER',
      'BERRY',
      'MANGO',
      'TOMATO',
      'CHICKEN',
      'SPICE',
      'ORIGINAL',
      'SMOKED',
      'HOT',
      'PERI',
      'PANEER',
      'COOKIES',
      'BISCUITS',
      'CHOCOLATE',
      'MILK',
      'COFFEE',
      'TEA',
      'JUICE',
    ];

    var brandLine = '';
    for (final line in validLines) {
      final matchingBrand = _matchBrand(line);
      if (matchingBrand != null) {
        brand = matchingBrand;
        brandLine = line;
        break;
      }
    }

    // A line that is just the brand (even misread, e.g. "BRlTANNIA") is not
    // the product name; "Tata Salt" still is.
    bool isBrandOnly(String line) {
      if (line != brandLine) return false;
      final tokenCount = line
          .replaceAll(RegExp("['’`]"), '')
          .split(RegExp(r'[^A-Za-z0-9&|]+'))
          .where((token) => token.isNotEmpty)
          .length;
      return tokenCount <= brand.split(' ').length;
    }

    bool hasDateLabel(String upper) =>
        _hasAnyLabel(upper, const ['MFG', 'MFD', 'EXP', 'BEST BEFORE', 'BB']);

    for (final line in validLines) {
      final upper = line.toUpperCase();

      if (_productKeywords.any(
        (keyword) => upper.contains(keyword),
      )) {
        final cleaned = _cleanup(line);

        if (cleaned.isNotEmpty &&
            cleaned.toUpperCase() != brand.toUpperCase() &&
            !isBrandOnly(line)) {
          name = cleaned;
          break;
        }
      }
    }

    if (name == 'Unknown Product') {
      for (final line in validLines) {
        final cleaned = _cleanup(line);
        final upper = cleaned.toUpperCase();

        if (cleaned.length >= 3 &&
            !_looksLikeDate(cleaned) &&
            !_looksLikeQuantity(cleaned) &&
            !_looksLikePrice(cleaned) &&
            !upper.contains('INGREDIENTS') &&
            !upper.contains('NET WT') &&
            !hasDateLabel(upper) &&
            cleaned.toUpperCase() != brand.toUpperCase()) {
          if (brand != 'Unknown Brand' &&
              (line == brandLine || upper.contains(brand.toUpperCase()))) {
            continue;
          }

          name = cleaned;
          break;
        }
      }
    }

    if (brand != 'Unknown Brand' && name == 'Unknown Product') {
      final brandIndex = validLines.indexOf(brandLine);

      if (brandIndex != -1) {
        for (var i = brandIndex + 1; i < validLines.length; i++) {
          final line = validLines[i];
          final cleaned = _cleanup(line);
          final upper = cleaned.toUpperCase();

          if (cleaned.isEmpty ||
              hasDateLabel(upper) ||
              upper.contains('NET WT') ||
              upper.contains('MRP') ||
              upper.contains('PRICE') ||
              _looksLikeDate(cleaned) ||
              _looksLikeQuantity(cleaned) ||
              _looksLikePrice(cleaned)) {
            continue;
          }

          if (frontProductKeywords.any((keyword) => upper.contains(keyword)) ||
              cleaned.length >= 3) {
            name = cleaned;
            break;
          }
        }
      }
    }

    return {
      'name': _cleanup(name),
      'brand': _cleanup(brand),
      'category': _guessCategory('$name $brand'),
    };
  }

  // Front parse that also uses text size: the product name is normally the
  // largest print on the pack (e.g. "marie" over "GOLD" under BRITANNIA).
  static Map<String, String> extractFrontDetailsFromOCR(
    String text,
    List<dynamic> detections,
  ) {
    final boxes = <OCRBox>[];
    for (final item in detections) {
      if (item is! Map) continue;
      // The date recognizer re-reads the same boxes as digits; skip it here.
      if (item['recognizer'] == 'custom_date') continue;
      final box = _toBox(item);
      if (box != null) boxes.add(box);
    }
    final details = extractFrontDetails(
      boxes.isEmpty ? text : boxes.map((box) => box.text).join('\n'),
    );
    final brand = details['brand']!;

    bool isNameCandidate(OCRBox box) {
      final value = _cleanup(box.text);
      final letters = RegExp(r'[A-Za-z]').allMatches(value).length;
      if (letters < 3 || letters < value.replaceAll(' ', '').length * 0.6) {
        return false;
      }
      final upper = value.toUpperCase();
      return !_isMarketingNoise(value) &&
          !_hasAnyLabel(upper, [..._mfdLabels, ..._expiryLabels, ..._otherLabels]) &&
          !_looksLikeQuantity(value) &&
          !_looksLikePrice(value) &&
          _matchBrand(value) == null;
    }

    final textDetails = {...details, 'name_source': 'text'};
    final candidates = boxes.where(isNameCandidate).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    if (candidates.isEmpty) return textDetails;
    final heights = boxes.map((box) => box.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];
    final largest = candidates.first;
    // Only trust size when the name clearly stands out from body text.
    if (largest.height < medianHeight * 1.3) return textDetails;

    // Join big words on the same or the next line ("marie" + "GOLD").
    final nameBoxes = candidates.where((box) {
      if (box.height < largest.height * 0.55) return false;
      if (identical(box, largest)) return true;
      final verticalGap = box.top > largest.bottom
          ? box.top - largest.bottom
          : largest.top > box.bottom
              ? largest.top - box.bottom
              : 0.0;
      final horizontalGap = box.left > largest.right
          ? box.left - largest.right
          : largest.left > box.right
              ? largest.left - box.right
              : 0.0;
      return verticalGap <= largest.height * 0.8 &&
          horizontalGap <= largest.height * 1.5;
    }).toList()
      ..sort((a, b) {
        final sameLine = (a.centerY - b.centerY).abs() <
            math.min(a.height, b.height) * 0.5;
        return sameLine
            ? a.left.compareTo(b.left)
            : a.centerY.compareTo(b.centerY);
      });

    final name = _titleCase(
      _cleanup(nameBoxes.map((box) => box.text).join(' ')),
    );
    var category = _guessCategory('$name $brand');
    if (category == 'Others') {
      category = _guessCategory(boxes.map((box) => box.text).join(' '));
    }
    return {
      'name': name,
      'brand': brand,
      'category': category,
      'name_source': 'size',
    };
  }

  // Our OCR is the primary source; the vision fallback is only asked when the
  // brand is unknown or the name was not found from clear, large print.
  static bool frontNeedsVisionFallback(Map<String, String> details) {
    final name = details['name'] ?? 'Unknown Product';
    final letters = RegExp(r'[A-Za-z]').allMatches(name).length;
    return details['brand'] == 'Unknown Brand' ||
        name == 'Unknown Product' ||
        letters < 4 ||
        details['name_source'] != 'size';
  }

  static Map<String, String> mergeVisionDetails(
    Map<String, String> ocr,
    Map<String, String> vision,
  ) {
    final brand = (vision['brand'] ?? '').trim();
    final name = _cleanup(vision['product_name'] ?? '');
    final category = vision['category'] ?? '';
    return {
      ...ocr,
      if (brand.isNotEmpty) 'brand': brand.toUpperCase(),
      if (name.isNotEmpty) 'name': _titleCase(name),
      if ((ocr['category'] ?? 'Others') == 'Others' &&
          category.isNotEmpty &&
          category != 'Others')
        'category': category,
      if (brand.isNotEmpty || name.isNotEmpty) 'name_source': 'vision',
    };
  }

  static OCRBox? _toBox(Map item) {
    final value = item['text'];
    final rawBox = item['box'];
    if (value is! String || rawBox is! List || rawBox.length != 4) return null;
    final points = <List<double>>[];
    for (final point in rawBox) {
      if (point is! List || point.length != 2) return null;
      final x = (point[0] as num?)?.toDouble();
      final y = (point[1] as num?)?.toDouble();
      if (x == null || y == null) return null;
      points.add([x, y]);
    }
    if (value.trim().isEmpty) return null;
    return OCRBox(value.trim(), points);
  }

  static bool _isValidDateToken(String text) {
    final value = text.trim();
    if (RegExp(r'^\d{6,8}$').hasMatch(value)) {
      return _isValidDateString(_cleanUndelimitedDate(value));
    }
    return _isValidDateString(_cleanDate(value));
  }

  // Keras-OCR returns lowercase; show "Marie Gold" rather than "marie gold".
  static String _titleCase(String value) => value
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word.length == 1
          ? word.toUpperCase()
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');

  // ============================================================
  // BACK SIDE
  // Quantity + Price + MFD + EXP
  // ============================================================

  static Map<String, String> extractBackDetailsFromOCR(
    String text,
    List<dynamic> detections,
  ) {
    final columnAwareText = _buildColumnAwareText(text, detections);
    final quantityRepair = _findUncertainQuantityRepair(detections);
    final repairedText = quantityRepair == null
        ? columnAwareText
        : '$columnAwareText\nNET QTY ${quantityRepair['quantity']}';
    final result = extractBackDetails(repairedText);
    if (quantityRepair != null &&
        result['quantity'] != null &&
        result['quantity'] != 'Not detected') {
      result['quantity_status'] = 'UNCERTAIN';
    }
    return result;
  }

  static String _buildColumnAwareText(
    String text,
    List<dynamic> detections,
  ) {
    final parsed = <OCRBox>[];
    for (final item in detections) {
      if (item is! Map) continue;
      final value = item['text'];
      final rawBox = item['box'];
      if (value is! String || rawBox is! List || rawBox.length != 4) continue;
      final points = <List<double>>[];
      for (final point in rawBox) {
        if (point is! List || point.length != 2) {
          points.clear();
          break;
        }
        final x = (point[0] as num?)?.toDouble();
        final y = (point[1] as num?)?.toDouble();
        if (x == null || y == null) {
          points.clear();
          break;
        }
        points.add([x, y]);
      }
      if (points.length != 4 || value.trim().isEmpty) continue;
      final candidate = OCRBox(value.trim(), points);
      final duplicateIndex = parsed.indexWhere(
        (existing) =>
            (existing.centerY - candidate.centerY).abs() <=
                math.max(existing.height, candidate.height) * 0.35 &&
            (existing.left - candidate.left).abs() <=
                math.max(existing.height, candidate.height) * 0.5 &&
            (existing.right - candidate.right).abs() <=
                math.max(existing.height, candidate.height) * 0.5,
      );
      if (duplicateIndex < 0) {
        parsed.add(candidate);
      } else {
        final existing = parsed[duplicateIndex];
        final existingNumeric = RegExp(r'^\d[\d.]*$').hasMatch(existing.text);
        final candidateNumeric = RegExp(r'^\d[\d.]*$').hasMatch(candidate.text);
        final existingDateLike = _looksLikeDate(existing.text);
        final candidateDateLike = _looksLikeDate(candidate.text);
        final existingLabel = _looksLikeStructuralLabel(existing.text);
        final existingValidDate = _isValidDateToken(existing.text);
        final candidateValidDate = _isValidDateToken(candidate.text);
        final preferCandidate = candidateNumeric &&
            !existingLabel &&
            (!existingNumeric ||
                (candidate.text.contains('.') && !existing.text.contains('.')));
        // A reading that decodes to a real date ("0710126") beats one that only
        // looks like a date ("0/0/20").
        if (existingValidDate != candidateValidDate) {
          if (candidateValidDate) parsed[duplicateIndex] = candidate;
        } else if (preferCandidate ||
            (candidateDateLike && !existingDateLike)) {
          parsed[duplicateIndex] = candidate;
        }
      }
    }

    if (parsed.isEmpty) return text;
    parsed.sort((a, b) {
      final y = a.centerY.compareTo(b.centerY);
      return y == 0 ? a.left.compareTo(b.left) : y;
    });

    final labelPattern = RegExp(
      r'\b(?:BATCH\s*CODE|MFD|MFG|PKD|PKDS|PKDE|PKO|USE\s*BY|EXP(?:IRY)?|'
      r'EXD|BB|BEST|BEFORE|BEST\s*BEFORE|MRP|NET|WEIGHT|WT|QTY|QUANTITY|USP|USE)\b',
      caseSensitive: false,
    );
    bool isLabelLike(String value) {
      return RegExp(
        r'^(?:BATCH|CODE|MFD|MFG|PKD|PKDE|PIKDE|USE|BY|EXP|EXPIRY|'
        r'BEST|BEFORE|MRP|NET|WEIGHT|WT|QTY|QUANTITY|USP|RS|INR)$',
        caseSensitive: false,
      ).hasMatch(value.trim());
    }

    final usedValues = <OCRBox>{};
    final associatedLines = <String>[];
    for (final label in _dateAwareLabelBoxes(parsed)
        .where((item) => labelPattern.hasMatch(item.text))) {
      final numericValueLabel = RegExp(
        r'\b(?:MRP|PRICE|SALE\s*PRICE|RS|INR)\b',
        caseSensitive: false,
      ).hasMatch(label.text);
      final candidates = parsed.where((item) {
        if (item == label ||
            usedValues.contains(item) ||
            item.left < label.left ||
            isLabelLike(item.text)) {
          return false;
        }
        if (numericValueLabel &&
            !RegExp(r'^\s*[\d.,]+\s*$').hasMatch(item.text)) {
          return false;
        }
        final verticalDistance = (item.centerY - label.centerY).abs();
        final sameRowLabel = RegExp(
          r'\b(?:NET|WEIGHT|WT|QTY|QUANTITY|MRP|PRICE|RS|INR)\b',
          caseSensitive: false,
        ).hasMatch(label.text);
        final tolerance = sameRowLabel
            ? math.max(label.height, item.height) * 0.8 + 12
            : (label.height + item.height) + 16;
        return verticalDistance <= tolerance;
      }).toList()
        ..sort((a, b) {
          final scoreA = (a.centerY - label.centerY).abs() +
              (a.left - label.right).clamp(0, double.infinity) * 0.02;
          final scoreB = (b.centerY - label.centerY).abs() +
              (b.left - label.right).clamp(0, double.infinity) * 0.02;
          final digitScoreA = numericValueLabel
              ? 0
              : -2 * RegExp(r'\d').allMatches(a.text).length;
          final digitScoreB = numericValueLabel
              ? 0
              : -2 * RegExp(r'\d').allMatches(b.text).length;
          final dateScoreA = _looksLikeDate(a.text) ? -40 : 0;
          final dateScoreB = _looksLikeDate(b.text) ? -40 : 0;
          final decimalScoreA =
              numericValueLabel && a.text.contains('.') ? -20 : 0;
          final decimalScoreB =
              numericValueLabel && b.text.contains('.') ? -20 : 0;
          return (scoreA + digitScoreA + dateScoreA + decimalScoreA)
              .compareTo(scoreB + digitScoreB + dateScoreB + decimalScoreB);
        });
      if (candidates.isEmpty) {
        associatedLines.add(label.text);
        continue;
      }
      final value = candidates.first;
      usedValues.add(value);
      associatedLines.add('${_canonicalDateLabel(label.text)} ${value.text}');
    }

    if (associatedLines.isEmpty) return text;
    return '${associatedLines.join('\n')}\n$text';
  }

  static Map<String, String>? _findUncertainQuantityRepair(
    List<dynamic> detections,
  ) {
    final boxes = <OCRBox>[];
    for (final item in detections) {
      if (item is! Map ||
          item['text'] is! String ||
          item['box'] is! List ||
          (item['box'] as List).length != 4) {
        continue;
      }
      final points = <List<double>>[];
      for (final point in item['box'] as List) {
        if (point is! List || point.length != 2) {
          points.clear();
          break;
        }
        final x = (point[0] as num?)?.toDouble();
        final y = (point[1] as num?)?.toDouble();
        if (x == null || y == null) {
          points.clear();
          break;
        }
        points.add([x, y]);
      }
      if (points.length == 4) {
        boxes.add(OCRBox((item['text'] as String).trim(), points));
      }
    }

    for (final token in boxes) {
      final rawToken = token.text.trim();
      if (!RegExp(r'^[iIl|OS]$').hasMatch(rawToken)) continue;
      final digit = switch (rawToken.toUpperCase()) {
        'I' || 'L' || '|' => '1',
        'O' => '0',
        'S' => '5',
        _ => null,
      };
      if (digit == null) continue;

      final unit = boxes
          .where((candidate) =>
              candidate != token &&
              candidate.centerX > token.centerX &&
              (candidate.centerY - token.centerY).abs() <=
                  math.max(token.height, candidate.height) * 0.8 &&
              candidate.centerX - token.centerX <=
                  math.max(token.height, candidate.height) * 2.5)
          .where((candidate) => _quantityUnit(candidate.text) != null)
          .fold<OCRBox?>(null, (closest, candidate) {
        if (closest == null || candidate.left < closest.left) {
          return candidate;
        }
        return closest;
      });
      final normalizedUnit = unit == null ? null : _quantityUnit(unit.text);
      if (normalizedUnit != null) {
        return {
          'quantity': '$digit $normalizedUnit',
        };
      }
    }
    return null;
  }

  static String? _quantityUnit(String value) {
    final normalized = value.trim().toLowerCase();
    if (RegExp(r'^(?:kg|k9|kq|kgs?)$').hasMatch(normalized)) {
      return 'kg';
    }
    if (RegExp(r'^(?:g|gm|gms?)$').hasMatch(normalized)) return 'g';
    if (RegExp(r'^(?:ml|m1)$').hasMatch(normalized)) return 'ml';
    if (RegExp(r'^(?:l|lt|ltr)$').hasMatch(normalized)) return 'l';
    return null;
  }

  static Map<String, String> extractBackDetails(String text) {
    String quantity = 'Not detected';
    String price = '0.00';
    String mfd = 'Not detected';
    String exp = 'Not detected';

    final normalizedText = _normalizeText(text);

    final lines = normalizedText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final monthNames = 'JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|'
        'JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|'
        'SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER';

    final datePattern = RegExp(
      r'(?<!\d)(?:'
              r'\d{1,2}\s*(?:[/\-\.]|\s+)\s*(?:\d{1,2}|(?:' +
          monthNames +
          r'))\s*(?:[/\-\.]|\s+)\s*\d{2,4}|'
              // Glued day-month-year such as 13NOV2025.
              r'\d{1,2}\s*(?:' +
          monthNames +
          r')\s*\d{2,4}|'
              r'(?:' +
          monthNames +
          r')\s*(?:[/\-\.]|\s+)\s*\d{1,2}\s*(?:[/\-\.]|\s+)\s*\d{2,4}'
              r')(?!\d)',
      caseSensitive: false,
    );

    final compactDatePattern = RegExp(
      r'(?<!\d)\d{1,2}\s*(?:/|\-|\.)\s*\d{1,2}\s*(?:/|\-|\.)\s*\d{2,4}(?!\d)',
      caseSensitive: false,
    );

    final undelimitedDatePattern = RegExp(
      r'\b\d{6,8}\b',
      caseSensitive: false,
    );

    final monthYearPattern = RegExp(
      r'(?:\d{1,2}\s*(?:/|\-|\.|\s)\s*(?:20)?\d{2}|'
              r'(?:' +
          monthNames +
          r')(?:20)?\d{2}|'
              r'(?:' +
          monthNames +
          r')\s*(?:/|\-|\.|\s)\s*(?:20)?\d{2})',
      caseSensitive: false,
    );

    final expiryKeywords = _expiryLabels;
    final mfdKeywords = _mfdLabels;

    final relativeExpiryRegex = RegExp(
      r'(?:BEST\s+BEFORE|BEST\s+BY|USE\s+BY|USE\s+WITHIN|CONSUME\s+WITHIN|'
      r'VALID\s+TILL|VALID\s+FOR|SHELF\s+LIFE|EXPIRY|EXP\s+IN)\s+'
      r'(?:OF\s+|IS\s+|UPTO\s+|UP\s+TO\s+|WITHIN\s+)?'
      r'(\d{1,2})\s*(MONTHS?|MTHS?|DAYS?|YEARS?)',
      caseSensitive: false,
    );

    final allDateCandidates = <String>[];
    for (final match in datePattern.allMatches(normalizedText)) {
      final candidate = _cleanDate(match.group(0)!);
      if (_isValidDateString(candidate) &&
          !allDateCandidates.contains(candidate)) {
        allDateCandidates.add(candidate);
      }
    }
    for (final line in lines) {
      final isoDate = _isoDate(line);
      if (isoDate != null && !allDateCandidates.contains(isoDate)) {
        allDateCandidates.add(isoDate);
      }
    }

    String labelLine(String value) =>
        _canonicalizeDateLabels(_stripCompanyPhrases(_normalizeLabel(value)));

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final upperLine = labelLine(line);
      final hasMfdLabel = _hasAnyLabel(upperLine, mfdKeywords);
      final hasExpiryLabel = _hasAnyLabel(upperLine, expiryKeywords);
      final hasDateLabel = hasMfdLabel || hasExpiryLabel;

      if (mfd == 'Not detected' && hasMfdLabel) {
        final segment = _labelSegment(line, expiry: false);
        final monthOnlyMatch = RegExp(
          r'\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s*[-/.]?\s*20\d{2}\b',
          caseSensitive: false,
        ).firstMatch(segment);
        final hasDayMonthName = RegExp(
          r'\b\d{1,2}\s*[-/. ]?\s*[A-Za-z]{3,9}\s*[-/. ]?\s*\d{2,4}\b',
          caseSensitive: false,
        ).hasMatch(segment);
        if (monthOnlyMatch != null &&
            !_looksLikeDate(segment) &&
            !hasDayMonthName) {
          final candidate = _cleanMonthYear(monthOnlyMatch.group(0)!);
          if (_isValidDateString(candidate)) mfd = candidate;
        }
        final match = _firstDateInLine(
          line,
          compactDatePattern,
          datePattern,
          monthYearPattern,
          undelimitedDatePattern: undelimitedDatePattern,
        );
        if (mfd == 'Not detected' &&
            match != null &&
            _isValidDateString(_cleanDate(match))) {
          mfd = _cleanDate(match);
        }
      }

      if (exp == 'Not detected' && hasExpiryLabel) {
        final segment = _labelSegment(line, expiry: true);
        final monthOnlyMatch = RegExp(
          r'\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s*[-/.]?\s*20\d{2}\b',
          caseSensitive: false,
        ).firstMatch(segment);
        final hasDayMonthName = RegExp(
          r'\b\d{1,2}\s*[-/. ]?\s*[A-Za-z]{3,9}\s*[-/. ]?\s*\d{2,4}\b',
          caseSensitive: false,
        ).hasMatch(segment);
        if (monthOnlyMatch != null &&
            !_looksLikeDate(segment) &&
            !hasDayMonthName) {
          final candidate = _cleanMonthYear(
            monthOnlyMatch.group(0)!,
            expiry: true,
          );
          if (_isValidDateString(candidate)) exp = candidate;
        }
        final match = _firstDateInLine(
          line,
          compactDatePattern,
          datePattern,
          monthYearPattern,
          expiry: true,
          undelimitedDatePattern: undelimitedDatePattern,
        );
        if (exp == 'Not detected' &&
            match != null &&
            _isValidDateString(_cleanDate(match))) {
          exp = _cleanDate(match);
        }
      }

      String? adjacentDate({
        required bool expiry,
      }) {
        final adjacentLines = <String>[
          if (lineIndex + 1 < lines.length) lines[lineIndex + 1],
          if (lineIndex > 0) lines[lineIndex - 1],
        ];
        for (final adjacentLine in adjacentLines) {
          // Never borrow the date that belongs to the other label, e.g. the
          // EXP line under a "Packed on" heading.
          final adjacentUpper = labelLine(adjacentLine);
          final belongsToOther = expiry
              ? _hasAnyLabel(adjacentUpper, mfdKeywords) &&
                  !_hasAnyLabel(adjacentUpper, expiryKeywords)
              : _hasAnyLabel(adjacentUpper, expiryKeywords) &&
                  !_hasAnyLabel(adjacentUpper, mfdKeywords);
          if (belongsToOther) continue;
          final hasDateShape = _looksLikeDate(adjacentLine) ||
              undelimitedDatePattern.hasMatch(adjacentLine) ||
              RegExp(
                r'\b\d{1,2}\s*(?:/|-|\.)\s*(?:\d{1,2}|[A-Za-z]{3,9})\s*(?:/|-|\.)\s*\d{2,4}\b',
                caseSensitive: false,
              ).hasMatch(adjacentLine);
          if (!hasDateShape) continue;
          final match = _firstDateInLine(
            adjacentLine,
            compactDatePattern,
            datePattern,
            monthYearPattern,
            expiry: expiry,
            undelimitedDatePattern: undelimitedDatePattern,
          );
          if (match != null && _isValidDateString(_cleanDate(match))) {
            return _cleanDate(match);
          }
        }
        return null;
      }

      if (mfd == 'Not detected' && hasMfdLabel) {
        final adjacent = adjacentDate(expiry: false);
        if (adjacent != null) mfd = adjacent;
      }
      if (exp == 'Not detected' &&
          hasExpiryLabel &&
          !relativeExpiryRegex.hasMatch(upperLine)) {
        final adjacent = adjacentDate(expiry: true);
        if (adjacent != null) exp = adjacent;
      }

      if (hasDateLabel) {
        for (final match in undelimitedDatePattern.allMatches(line)) {
          final candidate = _cleanUndelimitedDate(
            match.group(0)!,
            expiry: hasExpiryLabel,
          );
          if (_isValidDateString(candidate) &&
              !allDateCandidates.contains(candidate)) {
            allDateCandidates.add(candidate);
          }
        }
      }

    }

    // Shelf-life phrases ("Best before 6 months from mfg", "Use within 9
    // months") can appear before or after the MFD line, so resolve them last.
    if (exp == 'Not detected' && mfd != 'Not detected') {
      for (final line in lines) {
        final relativeMatch = relativeExpiryRegex.firstMatch(labelLine(line));
        if (relativeMatch == null) continue;
        final amount = int.tryParse(relativeMatch.group(1)!);
        final unit = relativeMatch.group(2)!.toLowerCase();
        if (amount == null) continue;
        final parsedMfd = _parseDateString(mfd);
        final expDate = unit.startsWith('day')
            ? parsedMfd.add(Duration(days: amount))
            : unit.startsWith('year')
                ? DateTime(
                    parsedMfd.year + amount, parsedMfd.month, parsedMfd.day)
                : DateTime(
                    parsedMfd.year, parsedMfd.month + amount, parsedMfd.day);
        exp = _formatDate(expDate);
        break;
      }
    }

    if (mfd == 'Not detected' &&
        exp == 'Not detected' &&
        allDateCandidates.length >= 2) {
      mfd = allDateCandidates.first;
      exp = allDateCandidates.last;
    } else if (mfd == 'Not detected' &&
        exp == 'Not detected' &&
        allDateCandidates.length == 1) {
      mfd = allDateCandidates.first;
    }

    if (mfd != 'Not detected' &&
        exp == 'Not detected' &&
        allDateCandidates.length >= 2) {
      final earliest = allDateCandidates.first;
      final latest = allDateCandidates.last;
      if (mfd == earliest) {
        exp = latest;
      }
    }

    if (mfd != 'Not detected' && exp != 'Not detected' && mfd == exp) {
      exp = 'Not detected';
    }

    if (mfd != 'Not detected' &&
        exp != 'Not detected' &&
        !_parseDateString(exp).isAfter(_parseDateString(mfd))) {
      exp = 'Not detected';
    }

    final quantityRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*'
      r'(kg|kgs|k9|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?|pcs|pc|units?|pkt|packs?|sachets?)',
      caseSensitive: false,
    );

    final netQuantityRegex = RegExp(
      r'(?:NET\s*(?:WT|WEIGHT|QTY|QUANTITY|CONTENT|VOLUME)|CONTENTS?)\s*[:\-]?\s*'
      r'(\d+(?:\.\d+)?)\s*'
      r'(kg|kgs|k9|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?)',
      caseSensitive: false,
    );

    final netQuantityMatch = netQuantityRegex.firstMatch(normalizedText);
    if (netQuantityMatch != null) {
      quantity =
          '${netQuantityMatch.group(1)} ${_normalizeUnit(netQuantityMatch.group(2)!)}';
    }

    if (quantity == 'Not detected') {
      final unitPriceLineRegex = RegExp(
        r'(?:\bper\b|/)\s*(?:kg|kgs|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?)\b',
        caseSensitive: false,
      );
      for (final line in lines) {
        if (unitPriceLineRegex.hasMatch(line)) continue;
        for (final match in quantityRegex.allMatches(line)) {
          final value = double.tryParse(match.group(1)!);

          if (value != null && value > 0 && value < 2000) {
            quantity = '${match.group(1)} ${_normalizeUnit(match.group(2)!)}';
            break;
          }
        }
        if (quantity != 'Not detected') break;
      }
    }

    if (quantity == 'Not detected') {
      final netWeightMatch = RegExp(
        r'net\s*wt\.?\s*(\d+(?:\.\d+)?)\s*(kg|kgs|g|gm|mg|l|lt|ltr|ml)',
        caseSensitive: false,
      ).firstMatch(normalizedText);

      if (netWeightMatch != null) {
        quantity = '${netWeightMatch.group(1)} ${netWeightMatch.group(2)}';
      }
    }

    final priceRegex = RegExp(
      r'(?:SALE\s*PRICE|MRP|MAX(?:IMUM)?\s*RETAIL\s*PRICE|PRICE)'
      r'\s*[:\-]?\s*'
      r'(?:₹|RS\.?|INR)?\s*'
      r'(\d+(?:\.\d{0,2})?)',
      caseSensitive: false,
    );

    final unitPriceLineRegex = RegExp(
      r'(?:\bper\b|/)\s*(?:kg|kgs|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?)\b',
      caseSensitive: false,
    );
    RegExpMatch? priceMatch;
    for (final line in lines) {
      final hasExplicitPriceLabel = RegExp(
        r'\b(?:MRP|SALE\s*PRICE|MAX(?:IMUM)?\s*RETAIL\s*PRICE)\b',
        caseSensitive: false,
      ).hasMatch(line);
      if (unitPriceLineRegex.hasMatch(line) && !hasExplicitPriceLabel) {
        continue;
      }
      final matches = priceRegex.allMatches(line).toList();
      if (matches.isNotEmpty) {
        priceMatch = matches.firstWhere(
          (match) => match.group(1)!.contains('.'),
          orElse: () => matches.first,
        );
        break;
      }
      if (hasExplicitPriceLabel) {
        final labelEnd = RegExp(
          r'\b(?:MRP|SALE\s*PRICE|MAX(?:IMUM)?\s*RETAIL\s*PRICE)\b',
          caseSensitive: false,
        ).firstMatch(line)?.end;
        if (labelEnd != null) {
          final numericCandidates = RegExp(
            r'\d+(?:\.\d*)?',
          ).allMatches(line.substring(labelEnd)).toList();
          if (numericCandidates.isNotEmpty) {
            final selected = numericCandidates.firstWhere(
              (match) => match.group(0)!.contains('.'),
              orElse: () => numericCandidates.first,
            );
            final selectedValue = selected.group(0)!;
            price = (double.tryParse(selectedValue) ?? 0).toStringAsFixed(2);
            if (price != '0.00') break;
          }
        }
      }
    }

    if (priceMatch != null) {
      final value = double.tryParse(priceMatch.group(1)!);

      if (value != null && value >= 0 && value < 100000) {
        price = value.toStringAsFixed(2);
      }
    }

    if (price == '0.00') {
      final currencyRegex = RegExp(
        r'(?:₹|RS\.?|INR)\s*'
        r'(\d+(?:\.\d{0,2})?)',
        caseSensitive: false,
      );

      RegExpMatch? currencyMatch;
      for (final line in lines) {
        if (unitPriceLineRegex.hasMatch(line)) continue;
        currencyMatch = currencyRegex.firstMatch(line);
        if (currencyMatch != null) break;
      }

      if (currencyMatch != null) {
        final value = double.tryParse(
          currencyMatch.group(1)!,
        );

        if (value != null && value >= 0 && value < 100000) {
          price = value.toStringAsFixed(2);
        }
      }
    }

    return {
      'quantity': quantity,
      'quantity_status': 'CERTAIN',
      'price': price,
      'mfd': mfd,
      'exp': exp,
    };
  }

  // ============================================================
  // COMBINE FRONT + BACK
  // ============================================================

  static Map<String, String> combineDetails(
    Map<String, String> front,
    Map<String, String> back,
  ) {
    final name = front['name'] ?? 'Unknown Product';
    final brand = front['brand'] ?? 'Unknown Brand';

    return {
      'name': name,
      'brand': brand,
      'category': front['category'] ?? _guessCategory('$name $brand'),
      'quantity': back['quantity'] ?? 'Not detected',
      'quantity_status': back['quantity_status'] ?? 'CERTAIN',
      'price': back['price'] ?? '0.00',
      'mfd': back['mfd'] ?? 'Not detected',
      'exp': back['exp'] ?? 'Not detected',
    };
  }

  // ============================================================
  // OLD ONE-SCAN METHOD — KEPT FOR COMPATIBILITY
  // ============================================================

  static Map<String, String> extractDetails(String text) {
    final front = extractFrontDetails(text);
    final back = extractBackDetails(text);
    return combineDetails(front, back);
  }

  static String _normalizeText(String text) {
    return text
        .replaceAll(RegExp(r'[×x]'), 'x')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static String _normalizeLabel(String line) {
    return line
        .toUpperCase()
        .replaceAll('MFO', 'MFG')
        .replaceAll('MFC', 'MFG')
        .replaceAll('EYP', 'EXP')
        .replaceAll('EXD', 'EXP')
        .replaceAll('EXPIRES', 'EXP')
        .replaceAll('E×P', 'EXP')
        .replaceAll('BEF0RE', 'BEFORE')
        .replaceAll(RegExp(r'\bPKDE\b', caseSensitive: false), 'PKD')
        .replaceAll(RegExp(r'\bPIKDE\b', caseSensitive: false), 'PKD')
        .replaceAll(RegExp(r'\bWEIGNT\b', caseSensitive: false), 'WEIGHT')
        .replaceAll('USEBY', 'USE BY')
        .replaceAll('BESTBEFORE', 'BEST BEFORE')
        .replaceAll(RegExp(r'[.:,;|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const _mfdLabels = <String>[
    'MFD',
    'MFG',
    'MFD DATE',
    'MFG DATE',
    'MFG DT',
    'MFD DT',
    'MANUFACTURE',
    'MANUFACTURED',
    'MANUFACTURED ON',
    'MANUFACTURING',
    'DATE OF MFG',
    'DATE OF MANUFACTURE',
    'PACKED',
    'PACKING',
    'PACKED ON',
    'PACK DATE',
    'PACKAGING DATE',
    'PACKAGED ON',
    'DATE OF PACKING',
    'DATE OF PACKAGING',
    'PKG DATE',
    'PKG DT',
    'PKDDATE',
    'PKD',
    'DOM',
  ];

  static const _expiryLabels = <String>[
    'EXP',
    'EXPIRY',
    'EXP DATE',
    'EXP DT',
    'EXPIRY DATE',
    'EXPIRE',
    'EXPIRED',
    'EXPIRING',
    'EXD',
    'BEST BEFORE',
    'BESTBEFORE',
    'BEST BY',
    'USE BY',
    'USEBY',
    'USE BEFORE',
    'CONSUME BEFORE',
    'VALID TILL',
    'SELL BY',
    'BB',
    'BBE',
  ];

  static const _otherLabels = <String>[
    'MRP',
    'NET WT',
    'NET WEIGHT',
    'NET QTY',
    'BATCH',
    'LOT',
  ];

  // Whole-word label match, so EXP does not fire inside EXPORT or DOM inside
  // KINGDOM, while still allowing digits glued on (EXP12/05/2026).
  static RegExp _labelRegex(String label) => RegExp(
        '(?<![A-Z])'
        '${RegExp.escape(label).replaceAll(r'\ ', ' ').replaceAll(' ', r'\s*')}'
        '(?![A-Z])',
      );

  static bool _hasAnyLabel(String upper, List<String> labels) =>
      labels.any((label) => _labelRegex(label).hasMatch(upper));

  // "Packed by", "Mfd by", "Manufactured in" name a company, not a date.
  static String _stripCompanyPhrases(String upper) => upper.replaceAll(
        RegExp(
          r'(?<![A-Z])(?:PACKED|PKD|MANUFACTURED|MANUFACTURER|MARKETED|MKTD|'
          r'MFD|MFG|DISTRIBUTED|IMPORTED)\s+(?:BY|FOR|IN|AT|UNDER)(?![A-Z])',
        ),
        'COMPANY',
      );

  static Match? _earliestLabel(String text, List<String> labels) {
    Match? best;
    for (final label in labels) {
      final match = _labelRegex(label).firstMatch(text);
      if (match == null) continue;
      if (best == null ||
          match.start < best.start ||
          (match.start == best.start && match.end > best.end)) {
        best = match;
      }
    }
    return best;
  }

  // Text after the MFD (or expiry) label, cut at the next label, so a line
  // like "MFD 01/05/25 EXP 01/11/25" yields a different date for each.
  static String _labelSegment(String line, {required bool expiry}) {
    final normalizedLine = _stripCompanyPhrases(_normalizeLabel(line));
    const allLabels = [..._mfdLabels, ..._expiryLabels, ..._otherLabels];
    final start =
        _earliestLabel(normalizedLine, expiry ? _expiryLabels : _mfdLabels) ??
            _earliestLabel(normalizedLine, allLabels);
    if (start == null) return normalizedLine;
    final rest = normalizedLine.substring(start.end);
    final next = _earliestLabel(rest, allLabels);
    final segment = next == null ? rest : rest.substring(0, next.start);
    return RegExp(r'\d').hasMatch(segment) ? segment : rest;
  }

  static String _canonicalizeDateLabels(String line) {
    final words = RegExp(r'[A-Z0-9]+', caseSensitive: false)
        .allMatches(line.toUpperCase())
        .map((match) => match.group(0)!)
        .toList();
    final hasBest = words.any((word) => _fuzzyLabelMatch(word, 'BEST'));
    final hasBefore = words.any((word) => _fuzzyLabelMatch(word, 'BEFORE'));
    final hasUse = words.any((word) => _fuzzyLabelMatch(word, 'USE'));
    final hasBy = words.any((word) => _fuzzyLabelMatch(word, 'BY'));

    if (hasBest && hasBefore) {
      return 'BEST BEFORE $line';
    }
    if (hasUse && hasBy) {
      return 'USE BY $line';
    }
    for (final label in [
      'PKD',
      'MFD',
      'MFG',
      'DOM',
      'EXP',
      'EXD',
      'BB',
    ]) {
      if (words.any((word) => _fuzzyLabelMatch(word, label))) {
        return '${_canonicalDateLabel(label)} $line';
      }
    }
    return line;
  }

  static String _canonicalDateLabel(String value) {
    final upper = value.toUpperCase().trim();
    if (upper == 'BB' ||
        _fuzzyLabelMatch(upper, 'EXP') ||
        _fuzzyLabelMatch(upper, 'EXD')) {
      return 'EXP';
    }
    if (_fuzzyLabelMatch(upper, 'USE') || upper == 'USE BY') {
      return 'USE BY';
    }
    if (upper == 'BEST BEFORE' ||
        _fuzzyLabelMatch(upper, 'BEST') ||
        _fuzzyLabelMatch(upper, 'BEFORE')) {
      return 'BEST BEFORE';
    }
    if (_fuzzyLabelMatch(upper, 'MFD') ||
        _fuzzyLabelMatch(upper, 'MFG') ||
        _fuzzyLabelMatch(upper, 'DOM') ||
        _fuzzyLabelMatch(upper, 'PKD') ||
        _fuzzyLabelMatch(upper, 'PKDS') ||
        _fuzzyLabelMatch(upper, 'PKDE') ||
        _fuzzyLabelMatch(upper, 'PKO')) {
      return 'MFD';
    }
    return value;
  }

  static bool _fuzzyLabelMatch(String value, String label) {
    final candidate = value.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    final target = label.toUpperCase();
    if (candidate == target) return true;
    if (candidate.isEmpty || target.isEmpty) return false;
    if ((candidate.length - target.length).abs() > 1) return false;
    var previous = List<int>.generate(target.length + 1, (i) => i);
    for (var i = 1; i <= candidate.length; i++) {
      final current = <int>[i];
      for (var j = 1; j <= target.length; j++) {
        current.add(math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + (candidate[i - 1] == target[j - 1] ? 0 : 1),
        ));
      }
      previous = current;
    }
    return previous.last <= 1;
  }

  static List<OCRBox> _dateAwareLabelBoxes(List<OCRBox> boxes) {
    final labels = <OCRBox>[];
    final used = <OCRBox>{};
    for (final box in boxes) {
      final word = box.text.trim();
      final isDateLabel = _fuzzyLabelMatch(word, 'PKD') ||
          _fuzzyLabelMatch(word, 'MFD') ||
          _fuzzyLabelMatch(word, 'MFG') ||
          _fuzzyLabelMatch(word, 'DOM') ||
          _fuzzyLabelMatch(word, 'EXP') ||
          _fuzzyLabelMatch(word, 'EXD') ||
          word.toUpperCase() == 'BB';
      if (isDateLabel) {
        labels.add(OCRBox(_canonicalDateLabel(word), box.points));
      }
    }
    for (final first in boxes) {
      final firstUpper = first.text.toUpperCase();
      if (!_fuzzyLabelMatch(firstUpper, 'USE') &&
          !_fuzzyLabelMatch(firstUpper, 'BEST')) {
        continue;
      }
      final second = boxes
          .where((item) =>
              item != first &&
              (item.centerY - first.centerY).abs() <=
                  math.max(first.height, item.height) * 0.8 &&
              item.left >= first.left &&
              (_fuzzyLabelMatch(item.text, 'BY') ||
                  _fuzzyLabelMatch(item.text, 'BEFORE')))
          .fold<OCRBox?>(null, (closest, item) {
        if (closest == null ||
            (item.left - first.right).abs() <
                (closest.left - first.right).abs()) {
          return item;
        }
        return closest;
      });
      if (second != null) {
        used.add(first);
        used.add(second);
        final left = math.min(first.left, second.left);
        final top = math.min(
          first.points.map((point) => point[1]).reduce(math.min),
          second.points.map((point) => point[1]).reduce(math.min),
        );
        final right = math.max(first.right, second.right);
        final bottom = math.max(
          first.points.map((point) => point[1]).reduce(math.max),
          second.points.map((point) => point[1]).reduce(math.max),
        );
        labels.add(OCRBox(
          first.text.toUpperCase().contains('BEST') ? 'BEST BEFORE' : 'USE BY',
          [
            [left, top],
            [right, top],
            [right, bottom],
            [left, bottom],
          ],
        ));
      }
    }
    return [
      ...labels,
      ...boxes.where((box) =>
          !used.contains(box) &&
          RegExp(r'\b(?:MRP|NET|WEIGHT|WT|QTY|QUANTITY|USP|RS|INR)\b',
                  caseSensitive: false)
              .hasMatch(box.text)),
    ];
  }

  static bool _looksLikeStructuralLabel(String value) {
    return RegExp(
      r'^(?:USE|BY|BEST|BEFORE|MFD|MFG|PKD|PKDS|PKDE|PKO|EXP|EXD|BB|'
      r'MRP|NET|WEIGHT|WT|QTY|QUANTITY|USP|RS|INR)$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  static String _normalizeUnit(String unit) {
    final value = unit.toLowerCase();
    if (value.startsWith('kg') || value == 'k9' || value.startsWith('kilogram'))
      return 'kg';
    if (value == 'gm' || value.startsWith('gram')) return 'g';
    if (value.startsWith('millilitre')) return 'ml';
    if (value.startsWith('litre') || value == 'lt' || value == 'ltr')
      return 'l';
    return value;
  }

  static List<String> _removeNoise(List<String> lines) {
    final noiseWords = [
      'YOUTUBE',
      'CAPSTONE',
      'SHIFT',
      'CTRL',
      'SEARCH',
      'KEYBOARD',
      'MONITOR',
      'DESKTOP',
      'ANDROID',
      'GOOGLE',
      'CAMERA',
      'HTTP',
      'WWW',
    ];

    return lines.where((line) {
      final upper = line.toUpperCase();

      if (line.length < 2) return false;

      if (noiseWords.any((noise) => upper.contains(noise))) {
        return false;
      }

      return true;
    }).toList();
  }

  static String _cleanDate(String date) {
    var normalized = date.trim();
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\.|-'), '/');
    normalized = normalized.replaceAll(RegExp(r'[^A-Za-z0-9/\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    final monthMap = {
      'JAN': '1',
      'JANUARY': '1',
      'FEB': '2',
      'FEBRUARY': '2',
      'MAR': '3',
      'MARCH': '3',
      'APR': '4',
      'APRIL': '4',
      'MAY': '5',
      'JUN': '6',
      'JUNE': '6',
      'JUL': '7',
      'JULY': '7',
      'AUG': '8',
      'AUGUST': '8',
      'SEP': '9',
      'SEPTEMBER': '9',
      'OCT': '10',
      'OCTOBER': '10',
      'NOV': '11',
      'NOVEMBER': '11',
      'DEC': '12',
      'DECEMBER': '12',
    };

    final dayMonthYearMatch = RegExp(
      r'^(\d{1,2})\s*(?:/|\s*)\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s*(?:/|\s*)\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (dayMonthYearMatch != null) {
      final day = _fixDigitSequence(dayMonthYearMatch.group(1)!);
      final month = monthMap[dayMonthYearMatch.group(2)!.toUpperCase()]!;
      final year = _fixDigitSequence(dayMonthYearMatch.group(3)!);
      return '$day/$month/${year.length == 2 ? '20$year' : year}';
    }

    final monthFirstMatch = RegExp(
      r'^(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s*(?:/|\s+)\s*(\d{1,2})\s*(?:/|\s+)\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (monthFirstMatch != null) {
      final month = monthMap[monthFirstMatch.group(1)!.toUpperCase()]!;
      final day = _fixDigitSequence(monthFirstMatch.group(2)!);
      final year = _fixDigitSequence(monthFirstMatch.group(3)!);
      return '$day/$month/${year.length == 2 ? '20$year' : year}';
    }

    final slashMatch = RegExp(
      r'^(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);

    final spacedNumericMatch = RegExp(
      r'^(\d{1,2})\s+(\d{1,2})\s+(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (spacedNumericMatch != null) {
      return _dayMonthYear(
        _fixDigitSequence(spacedNumericMatch.group(1)!),
        _fixDigitSequence(spacedNumericMatch.group(2)!),
        _fixDigitSequence(spacedNumericMatch.group(3)!),
      );
    }

    if (slashMatch != null) {
      return _dayMonthYear(
        _fixDigitSequence(slashMatch.group(1)!),
        _fixDigitSequence(slashMatch.group(2)!),
        _fixDigitSequence(slashMatch.group(3)!),
      );
    }

    final monthYearMatch = RegExp(
      r'^(\d{1,2})\s*/\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (monthYearMatch != null) {
      final month = _fixDigitSequence(monthYearMatch.group(1)!);
      final year = _fixDigitSequence(monthYearMatch.group(2)!);
      return '1/${int.parse(month)}/${year.length == 2 ? '20$year' : year}';
    }

    final directText = normalized.replaceAll(' ', '/');
    final fallback = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(directText);
    if (fallback != null) {
      return '${_fixDigitSequence(fallback.group(1)!)}'
          '/${_fixDigitSequence(fallback.group(2)!)}'
          '/${_fixDigitSequence(fallback.group(3)!)}';
    }

    return normalized;
  }

  // Indian packs print DD/MM/YYYY; imported ones may use MM/DD/YYYY. Swap only
  // when the second number cannot be a month and the first can.
  static String _dayMonthYear(String day, String month, String year) {
    final fullYear = year.length == 2 ? '20$year' : year;
    final dayValue = int.tryParse(day);
    final monthValue = int.tryParse(month);
    if (dayValue != null &&
        monthValue != null &&
        monthValue > 12 &&
        monthValue <= 31 &&
        dayValue >= 1 &&
        dayValue <= 12) {
      return '$month/$day/$fullYear';
    }
    return '$day/$month/$fullYear';
  }

  static String _fixDigitSequence(String value) {
    final corrected = value
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('L', '1')
        .replaceAll('S', '5')
        .replaceAll('s', '5')
        .replaceAll('B', '8')
        .replaceAll('b', '8')
        .replaceAll('Z', '2')
        .replaceAll('z', '2')
        .replaceAll('G', '6')
        .replaceAll('g', '6')
        .replaceAll('?', '7');
    return corrected;
  }

  static DateTime _parseDateString(String value) {
    final clean = value.trim();
    final parts = clean.split('/');
    if (parts.length == 3) {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      return DateTime(year, month, day);
    }
    throw FormatException('Unsupported date format: $value');
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  static String _cleanup(String input) {
    return input
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _firstDateInLine(
    String line,
    RegExp compactDatePattern,
    RegExp datePattern,
    RegExp? monthYearPattern, {
    bool expiry = false,
    RegExp? undelimitedDatePattern,
  }) {
    final repairedLine = _repairDateCandidateLine(line, expiry: expiry);

    // Skip junk like "0/0/20" so a real date later on the line still wins.
    for (final compactMatch in compactDatePattern.allMatches(repairedLine)) {
      if (_isValidDateString(_cleanDate(compactMatch.group(0)!))) {
        return compactMatch.group(0)!;
      }
    }

    final isoDate = _isoDate(repairedLine);
    if (isoDate != null) return isoDate;

    if (undelimitedDatePattern != null) {
      for (final undelimitedMatch
          in undelimitedDatePattern.allMatches(repairedLine)) {
        final candidate = _cleanUndelimitedDate(
          undelimitedMatch.group(0)!,
          expiry: expiry,
        );
        if (_isValidDateString(candidate)) return candidate;
      }
    }

    final invalidCompact = compactDatePattern.firstMatch(repairedLine);
    if (invalidCompact != null) {
      return invalidCompact.group(0)!;
    }

    final match = datePattern.firstMatch(repairedLine);
    if (match != null) {
      return match.group(0)!;
    }

    final monthNameYearMatch = RegExp(
      r'\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|'
      r'JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|'
      r'SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s*[/\-.]?\s*(?:20)?\d{2}\b',
      caseSensitive: false,
    ).firstMatch(repairedLine);
    if (monthNameYearMatch != null) {
      return _cleanMonthYear(monthNameYearMatch.group(0)!, expiry: expiry);
    }

    if (monthYearPattern != null) {
      final monthYearMatch = monthYearPattern.firstMatch(repairedLine);
      if (monthYearMatch != null) {
        return _cleanMonthYear(monthYearMatch.group(0)!, expiry: expiry);
      }
    }

    return null;
  }

  // Year-first dates such as 2026-05-12, common on imported products.
  static String? _isoDate(String text) {
    for (final match in RegExp(
      r'(?<!\d)(20\d{2})\s*[/\-. ]\s*(\d{1,2})\s*[/\-. ]\s*(\d{1,2})(?!\d)',
    ).allMatches(text)) {
      final candidate =
          '${int.parse(match.group(3)!)}/${int.parse(match.group(2)!)}/${match.group(1)}';
      if (_isValidDateString(candidate)) return candidate;
    }
    return null;
  }

  static String _cleanUndelimitedDate(
    String value, {
    bool expiry = false,
  }) {
    final digits = _fixDigitSequence(value);
    final candidates = <String>[];
    void add(String day, String month, String year) {
      final candidate = '$day/$month/${year.length == 2 ? '20$year' : year}';
      if (_isValidDateString(candidate) && !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    // OCR often reads a printed "/" as "1": 06/04/27 -> 06104127, and may
    // drop one slash entirely: 07/10/26 -> 0710126.
    if (digits.length == 8) {
      add(digits.substring(0, 2), digits.substring(2, 4), digits.substring(4));
      if (candidates.isEmpty && digits[2] == '1' && digits[5] == '1') {
        add(digits.substring(0, 2), digits.substring(3, 5), digits.substring(6));
      }
    } else if (digits.length == 7) {
      if (digits[4] == '1') {
        add(digits.substring(0, 2), digits.substring(2, 4), digits.substring(5));
      }
      if (digits[2] == '1') {
        add(digits.substring(0, 2), digits.substring(3, 5), digits.substring(5));
      }
    } else if (digits.length == 6) {
      add(digits.substring(0, 2), digits.substring(2, 4), digits.substring(4));
    }
    if (candidates.isEmpty) {
      if (digits.length == 8) {
        return '${digits.substring(0, 2)}/${digits.substring(2, 4)}/${digits.substring(4)}';
      }
      if (digits.length == 6) {
        return '${digits.substring(0, 2)}/${digits.substring(2, 4)}/20${digits.substring(4)}';
      }
      return value;
    }
    if (candidates.length == 1) return candidates.first;
    // Ambiguous reading: packed dates are recent past, so take the latest one
    // not in the future; for expiry take the latest.
    final now = DateTime.now();
    final parsed = candidates.map(_parseDateString).toList()..sort();
    final notFuture = parsed.where((date) => !date.isAfter(now)).toList();
    final chosen = expiry || notFuture.isEmpty ? parsed.last : notFuture.last;
    return candidates.firstWhere((value) => _parseDateString(value) == chosen);
  }

  static String _repairDateCandidateLine(String line, {bool expiry = false}) {
    return _repairDateCandidate(_labelSegment(line, expiry: expiry));
  }

  static String _repairDateCandidate(String input) {
    final map = {
      'O': '0',
      'o': '0',
      'I': '1',
      'l': '1',
      'L': '1',
      'S': '5',
      's': '5',
      'B': '8',
      'b': '8',
      'Z': '2',
      'z': '2',
      'G': '6',
      'g': '6',
      '?': '7',
    };

    final repaired = StringBuffer();
    final regex = RegExp(r'[A-Za-z]+|[0-9]+|[^A-Za-z0-9]+');

    for (final match in regex.allMatches(input)) {
      final token = match.group(0)!;
      final upperToken = token.toUpperCase();

      if (RegExp(r'^[A-Za-z]+$').hasMatch(token) &&
          _monthNumber(upperToken) != null) {
        repaired.write(token);
        continue;
      }

      final correctedToken = token.split('').map((char) {
        if (RegExp(r'[A-Za-z?]').hasMatch(char)) {
          return map[char] ?? char.toUpperCase();
        }
        return char;
      }).join();

      repaired.write(correctedToken);
    }

    final normalized =
        repaired.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (RegExp(r'^\d{1,2}\s+\d{1,2}\s+\d{2,4}$').hasMatch(normalized)) {
      return normalized.replaceAll(RegExp(r'\s+'), '/');
    }

    return normalized;
  }

  static String _cleanMonthYear(String value, {bool expiry = false}) {
    final compactMonthMatch = RegExp(
      r'^(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(20)?(\d{2})$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (compactMonthMatch != null) {
      final month = _monthNumber(compactMonthMatch.group(1)!);
      final year = int.parse(
          '${compactMonthMatch.group(2) ?? '20'}${compactMonthMatch.group(3)!}');
      final day = expiry ? DateTime(year, month! + 1, 0).day : 1;
      return '$day/$month/$year';
    }

    final parts = value
        .trim()
        .replaceAll('.', '/')
        .replaceAll('-', '/')
        .split(RegExp(r'[/\s]+'));
    if (parts.length != 2) return value.trim();
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first != null && second != null) {
      final year = second < 100 ? 2000 + second : second;
      final month = first;
      final day = expiry ? DateTime(year, month + 1, 0).day : 1;
      return '$day/${month.toString()}/$year';
    }
    final month = _monthNumber(parts[0]);
    final yearValue = int.tryParse(parts[1]);
    if (month == null || yearValue == null) return value.trim();
    final year = yearValue < 100 ? 2000 + yearValue : yearValue;
    final day = expiry ? DateTime(year, month + 1, 0).day : 1;
    return '$day/$month/$year';
  }

  static int? _monthNumber(String value) {
    const months = <String, int>{
      'JAN': 1,
      'JANUARY': 1,
      'FEB': 2,
      'FEBRUARY': 2,
      'MAR': 3,
      'MARCH': 3,
      'APR': 4,
      'APRIL': 4,
      'MAY': 5,
      'JUN': 6,
      'JUNE': 6,
      'JUL': 7,
      'JULY': 7,
      'AUG': 8,
      'AUGUST': 8,
      'SEP': 9,
      'SEPTEMBER': 9,
      'OCT': 10,
      'OCTOBER': 10,
      'NOV': 11,
      'NOVEMBER': 11,
      'DEC': 12,
      'DECEMBER': 12,
    };
    return months[value.toUpperCase()];
  }

  static bool _isValidDateString(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null ||
        month == null ||
        year == null ||
        year < 2000 ||
        year > 2100) return false;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _looksLikeDate(String text) {
    return RegExp(
      r'\d{1,2}\s*[/\-\.]\s*\d{1,2}\s*[/\-\.]\s*\d{2,4}',
    ).hasMatch(text);
  }

  static bool _looksLikeQuantity(String text) {
    return RegExp(
      r'\d+(?:\.\d+)?\s*'
      r'(kg|g|mg|l|ml|pcs|units|pkt|pack)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _looksLikePrice(String text) {
    return RegExp(
      r'(₹|RS\.?|INR|MRP)\s*\d+',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String _guessCategory(String name) {
    final n = name.toLowerCase();

    if (RegExp(
      r'milk|curd|cheese|butter|paneer|ghee|yogurt',
    ).hasMatch(n)) {
      return 'Dairy';
    }

    if (RegExp(
      r'rice|atta|dal|wheat|flour|grain|pulse|oats|cereal',
    ).hasMatch(n)) {
      return 'Grains';
    }

    if (RegExp(
      r'biscuit|chip|snack|chocolate|cookie|kurkure|lays|noodles|bhujia|'
      r'namkeen|mixture|sev\b|chakli|wafer|crisps|puffs|angles|cracker|cake|'
      r'rusk|fills|bingo|candy|toffee',
    ).hasMatch(n)) {
      return 'Snacks';
    }

    if (RegExp(
      r'coke|juice|water|tea|coffee|drink|pepsi|soda|cola|squash|sharbat|'
      r'lassi|horlicks|bournvita|complan',
    ).hasMatch(n)) {
      return 'Beverages';
    }

    if (RegExp(
      r'soap|shampoo|detergent|cleaner|surf|ariel|toothpaste|handwash|'
      r'dishwash|colgate|dettol|harpic',
    ).hasMatch(n)) {
      return 'Household';
    }

    if (RegExp(
      r'oil|salt|sugar|masala|spice|sauce|ketchup|jam|pickle|achar|chutney|'
      r'honey|vinegar|mayonnaise|besan|sooji|rava|maida|poha',
    ).hasMatch(n)) {
      return 'Groceries';
    }

    return 'Others';
  }
}
