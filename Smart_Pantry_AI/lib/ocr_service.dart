class OCRService {
  static const _knownBrands = <String>[
    'PARLE AGRO', 'MOTHER DAIRY', 'SURF EXCEL', 'AASHIRVAAD',
    'BRITANNIA', 'HALDIRAM', 'KURKURE', 'KELLOGGS', 'COLGATE',
    'PEPSODENT', 'HORLICKS', 'BOURNVITA', 'NESTLE', 'MAGGI', 'AMUL',
    'TATA', 'DABUR', 'PARLE', 'ITC', 'CADBURY', 'PANTENE', 'DOVE',
    'ARIEL', 'EVEREST', 'FORTUNE', 'SAFFOLA', 'PEPSI', 'COKE', 'LAYS',
    'NANDINI', 'HERITAGE', 'AACHI', 'PRIYA', 'MDH', 'MTR', 'MARICO',
    'P&G', 'HUL', 'RED LABEL', 'BROOKE BOND', 'SUNFEAST', 'MONACO',
    'GOOD DAY', 'OREO', 'FROOTI', 'THUMS UP', 'COCA COLA', 'TIGER',
  ];

  static const _productKeywords = <String>[
    'MILK', 'CURD', 'PANEER', 'BUTTER', 'CHEESE', 'GHEE', 'ATTA', 'RICE',
    'DAL', 'PULSE', 'SALT', 'SUGAR', 'OIL', 'COFFEE', 'TEA', 'JUICE',
    'SODA', 'CHIPS', 'BISCUIT', 'COOKIE', 'JAM', 'KETCHUP', 'SAUCE',
    'NOODLE', 'PASTA', 'WHEAT', 'FLOUR', 'CEREAL', 'OATS', 'SPICE',
    'MASALA', 'SNACK', 'CHOCOLATE', 'SOAP', 'SHAMPOO', 'DETERGENT',
    'CLEANER', 'BIRYANI', 'CHICKEN', 'TURMERIC', 'BASMATI', 'NIMKI',
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

    final validLines = _removeNoise(lines);

    final frontProductKeywords = [
      'CREAM', 'ONION', 'CLASSIC', 'MASALA', 'CHILLI', 'SALT',
      'NIMK', 'CHEESE', 'POTATO', 'CHIPS', 'CRISPS', 'FRIES',
      'WAFER', 'BERRY', 'MANGO', 'TOMATO', 'CHICKEN', 'SPICE',
      'ORIGINAL', 'SMOKED', 'HOT', 'PERI', 'PANEER', 'COOKIES',
      'BISCUITS', 'CHOCOLATE', 'MILK', 'COFFEE', 'TEA', 'JUICE',
    ];

    for (final line in validLines) {
      final upper = line.toUpperCase();

      final matchingBrand = _knownBrands.firstWhere(
        (brandName) => _containsWord(upper, brandName),
        orElse: () => '',
      );

      if (matchingBrand.isNotEmpty) {
        brand = matchingBrand;
        break;
      }
    }

    for (final line in validLines) {
      final upper = line.toUpperCase();

      if (_productKeywords.any(
        (keyword) => upper.contains(keyword),
      )) {
        final cleaned = _cleanup(line);

        if (cleaned.isNotEmpty &&
            cleaned.toUpperCase() != brand.toUpperCase()) {
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
            !upper.contains('MFG') &&
            !upper.contains('MFD') &&
            !upper.contains('EXP') &&
            !upper.contains('BEST BEFORE') &&
            !upper.contains('BB') &&
            cleaned.toUpperCase() != brand.toUpperCase()) {
          if (brand != 'Unknown Brand' && upper.contains(brand.toUpperCase())) {
            continue;
          }

          name = cleaned;
          break;
        }
      }
    }

    if (brand != 'Unknown Brand' && name == 'Unknown Product') {
      final brandIndex = validLines.indexWhere(
        (line) => line.toUpperCase().contains(brand.toUpperCase()),
      );

      if (brandIndex != -1) {
        for (var i = brandIndex + 1; i < validLines.length; i++) {
          final line = validLines[i];
          final cleaned = _cleanup(line);
          final upper = cleaned.toUpperCase();

          if (cleaned.isEmpty ||
              upper.contains('MFG') ||
              upper.contains('MFD') ||
              upper.contains('BB') ||
              upper.contains('EXP') ||
              upper.contains('BEST BEFORE') ||
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

  // ============================================================
  // BACK SIDE
  // Quantity + Price + MFD + EXP
  // ============================================================

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

    final monthNames =
        'JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|'
        'JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|'
        'SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER';

    final datePattern = RegExp(
      r'(?:'
      r'\d{1,2}\s*(?:[/\-\.]|\s+)\s*(?:\d{1,2}|(?:' + monthNames + r'))\s*(?:[/\-\.]|\s+)\s*\d{2,4}|'
      r'(?:' + monthNames + r')\s*(?:[/\-\.]|\s+)\s*\d{1,2}\s*(?:[/\-\.]|\s+)\s*\d{2,4}'
      r')',
      caseSensitive: false,
    );

    final compactDatePattern = RegExp(
      r'\d{1,2}\s*(?:/|\-|\.)\s*\d{1,2}\s*(?:/|\-|\.)\s*\d{2,4}',
      caseSensitive: false,
    );

    final monthYearPattern = RegExp(
      r'(?:\d{1,2}\s*(?:/|\-|\.|\s)\s*(?:20)?\d{2}|'
      r'(?:' + monthNames + r')\s*(?:/|\-|\.|\s)\s*(?:20)?\d{2})',
      caseSensitive: false,
    );

    final expiryKeywords = [
      'EXP',
      'EXPIRY',
      'EXP DATE',
      'EXPIRY DATE',
      'BEST BEFORE',
      'BESTBEFORE',
      'BEST BY',
      'USE BY',
      'USEBY',
      'VALID TILL',
      'SELL BY',
      'BB',
    ];

    final mfdKeywords = [
      'MFD',
      'MFG',
      'MFD DATE',
      'MFG DATE',
      'MANUFACTURE',
      'MANUFACTURING',
      'DATE OF MFG',
      'PACKED',
      'PACKING',
      'PACK DATE',
      'PKDDATE',
      'PKD',
      'DOM',
    ];

    final relativeExpiryRegex = RegExp(
      r'(?:BEST\s+BEFORE|BEST\s+BY|USE\s+BY|VALID\s+TILL)\s+(\d{1,2})\s*(MONTHS?|DAYS?|YEARS?)',
      caseSensitive: false,
    );

    final allDateCandidates = <String>[];
    for (final match in datePattern.allMatches(normalizedText)) {
      final candidate = _cleanDate(match.group(0)!);
      if (_isValidDateString(candidate) && !allDateCandidates.contains(candidate)) {
        allDateCandidates.add(candidate);
      }
    }

    for (final line in lines) {
      final upperLine = _normalizeLabel(line);

      if (mfd == 'Not detected' && mfdKeywords.any((keyword) => upperLine.contains(keyword))) {
        final match = _firstDateInLine(line, compactDatePattern, datePattern, monthYearPattern);
        if (match != null && _isValidDateString(_cleanDate(match))) {
          mfd = _cleanDate(match);
        }
      }

      if (exp == 'Not detected' && expiryKeywords.any((keyword) => upperLine.contains(keyword))) {
        final match = _firstDateInLine(line, compactDatePattern, datePattern, monthYearPattern, expiry: true);
        if (match != null && _isValidDateString(_cleanDate(match))) {
          exp = _cleanDate(match);
        }
      }

      if (exp == 'Not detected' && mfd != 'Not detected') {
        final relativeMatch = relativeExpiryRegex.firstMatch(upperLine);
        if (relativeMatch != null) {
          final amount = int.tryParse(relativeMatch.group(1)!);
          final unit = relativeMatch.group(2)!.toLowerCase();
          if (amount != null && mfd != 'Not detected') {
            final parsedMfd = _parseDateString(mfd);
            final expDate = unit.startsWith('day')
                ? parsedMfd.add(Duration(days: amount))
                : unit.startsWith('year')
                    ? DateTime(parsedMfd.year + amount, parsedMfd.month, parsedMfd.day)
                    : DateTime(parsedMfd.year, parsedMfd.month + amount, parsedMfd.day);
            exp = _formatDate(expDate);
          }
        }
      }
    }

    if (mfd == 'Not detected' && exp == 'Not detected' && allDateCandidates.length >= 2) {
      mfd = allDateCandidates.first;
      exp = allDateCandidates.last;
    } else if (mfd == 'Not detected' && exp == 'Not detected' && allDateCandidates.length == 1) {
      mfd = allDateCandidates.first;
    }

    if (mfd != 'Not detected' && exp == 'Not detected' && allDateCandidates.length >= 2) {
      final earliest = allDateCandidates.first;
      final latest = allDateCandidates.last;
      if (mfd == earliest) {
        exp = latest;
      }
    }

    if (mfd != 'Not detected' && exp != 'Not detected' && mfd == exp) {
      exp = 'Not detected';
    }

    if (mfd != 'Not detected' && exp != 'Not detected' &&
        !_parseDateString(exp).isAfter(_parseDateString(mfd))) {
      exp = 'Not detected';
    }

    final quantityRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*'
      r'(kg|kgs|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?|pcs|pc|units?|pkt|packs?|sachets?)',
      caseSensitive: false,
    );

    final netQuantityRegex = RegExp(
      r'(?:NET\s*(?:WT|WEIGHT|QTY|CONTENT|VOLUME)|CONTENTS?)\s*[:\-]?\s*'
      r'(\d+(?:\.\d+)?)\s*'
      r'(kg|kgs|kilograms?|g|gm|grams?|mg|l|lt|ltr|litres?|ml|millilitres?)',
      caseSensitive: false,
    );

    final netQuantityMatch = netQuantityRegex.firstMatch(normalizedText);
    if (netQuantityMatch != null) {
      quantity = '${netQuantityMatch.group(1)} ${_normalizeUnit(netQuantityMatch.group(2)!)}';
    }

    for (final match in quantity == 'Not detected'
        ? quantityRegex.allMatches(normalizedText)
        : const <RegExpMatch>[]) {
      final value = double.tryParse(match.group(1)!);

      if (value != null && value > 0 && value < 2000) {
        quantity = '${match.group(1)} ${_normalizeUnit(match.group(2)!)}';
        break;
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
      r'(\d+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );

    final priceMatch = priceRegex.firstMatch(normalizedText);

    if (priceMatch != null) {
      final value = double.tryParse(priceMatch.group(1)!);

      if (value != null && value >= 0 && value < 100000) {
        price = value.toStringAsFixed(2);
      }
    }

    if (price == '0.00') {
      final currencyRegex = RegExp(
        r'(?:₹|RS\.?|INR)\s*'
        r'(\d+(?:\.\d{1,2})?)',
        caseSensitive: false,
      );

      final currencyMatch =
          currencyRegex.firstMatch(normalizedText);

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
    return line.toUpperCase()
        .replaceAll('MFO', 'MFG')
        .replaceAll('MFC', 'MFG')
        .replaceAll('EYP', 'EXP')
        .replaceAll('E×P', 'EXP')
        .replaceAll('BEF0RE', 'BEFORE')
      .replaceAll('USEBY', 'USE BY')
      .replaceAll('BESTBEFORE', 'BEST BEFORE')
      .replaceAll(RegExp(r'[.:,;|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeUnit(String unit) {
    final value = unit.toLowerCase();
    if (value.startsWith('kg') || value.startsWith('kilogram')) return 'kg';
    if (value == 'gm' || value.startsWith('gram')) return 'g';
    if (value.startsWith('millilitre')) return 'ml';
    if (value.startsWith('litre') || value == 'lt' || value == 'ltr') return 'l';
    return value;
  }

  static List<String> _removeNoise(List<String> lines) {
    final noiseWords = [
      'YOUTUBE', 'CAPSTONE', 'SHIFT', 'CTRL', 'SEARCH',
      'KEYBOARD', 'MONITOR', 'DESKTOP', 'ANDROID', 'GOOGLE',
      'CAMERA', 'HTTP', 'WWW',
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
      'JAN': '1', 'JANUARY': '1',
      'FEB': '2', 'FEBRUARY': '2',
      'MAR': '3', 'MARCH': '3',
      'APR': '4', 'APRIL': '4',
      'MAY': '5',
      'JUN': '6', 'JUNE': '6',
      'JUL': '7', 'JULY': '7',
      'AUG': '8', 'AUGUST': '8',
      'SEP': '9', 'SEPTEMBER': '9',
      'OCT': '10', 'OCTOBER': '10',
      'NOV': '11', 'NOVEMBER': '11',
      'DEC': '12', 'DECEMBER': '12',
    };

    final dayMonthYearMatch = RegExp(
      r'^(\d{1,2})\s*(?:/|\s+)\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|JANUARY|FEBRUARY|MARCH|APRIL|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s*(?:/|\s+)\s*(\d{2,4})$',
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
      final day = _fixDigitSequence(spacedNumericMatch.group(1)!);
      final month = _fixDigitSequence(spacedNumericMatch.group(2)!);
      final year = _fixDigitSequence(spacedNumericMatch.group(3)!);
      return '$day/$month/${year.length == 2 ? '20$year' : year}';
    }

    if (slashMatch != null) {
      final day = _fixDigitSequence(slashMatch.group(1)!);
      final month = _fixDigitSequence(slashMatch.group(2)!);
      final year = _fixDigitSequence(slashMatch.group(3)!);
      return '$day/$month/${year.length == 2 ? '20$year' : year}';
    }

    final monthYearMatch = RegExp(
      r'^(\d{1,2})\s*/\s*(\d{2,4})$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (monthYearMatch != null) {
      final month = _fixDigitSequence(monthYearMatch.group(1)!);
      final year = _fixDigitSequence(monthYearMatch.group(2)!);
      return '1/$month/${year.length == 2 ? '20$year' : year}';
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
  }
  ) {
    final repairedLine = _repairDateCandidateLine(line);

    final compactMatch = compactDatePattern.firstMatch(repairedLine);
    if (compactMatch != null) {
      return compactMatch.group(0)!;
    }

    final match = datePattern.firstMatch(repairedLine);
    if (match != null) {
      return match.group(0)!;
    }

    if (monthYearPattern != null) {
      final monthYearMatch = monthYearPattern.firstMatch(repairedLine);
      if (monthYearMatch != null) {
        return _cleanMonthYear(monthYearMatch.group(0)!, expiry: expiry);
      }
    }

    return null;
  }

  static String _repairDateCandidateLine(String line) {
    final normalizedLine = _normalizeLabel(line);

    final labels = [
      'MFD', 'MFG', 'PKD', 'EXP', 'EXPIRY', 'USE BY', 'BEST BEFORE',
      'BESTBEFORE', 'USEBY', 'MANUFACTURED', 'MANUFACTURING', 'PACKED ON',
      'PACK DATE', 'PKDDATE', 'DATE OF MFG', 'DATE OF MANUFACTURE',
      'DOM', 'MRP', 'NET WT', 'NET WEIGHT',
    ];

    final upper = normalizedLine.toUpperCase();
    for (final label in labels) {
      final index = upper.indexOf(label);
      if (index >= 0) {
        final candidate = normalizedLine.substring(index + label.length);
        return _repairDateCandidate(candidate);
      }
    }
    return _repairDateCandidate(normalizedLine);
  }

  static String _repairDateCandidate(String input) {
    final map = {
      'O': '0', 'o': '0',
      'I': '1', 'l': '1', 'L': '1',
      'S': '5', 's': '5',
      'B': '8', 'b': '8',
      'Z': '2', 'z': '2',
      'G': '6', 'g': '6',
      '?': '7',
    };

    final repaired = StringBuffer();
    final regex = RegExp(r'[A-Za-z]+|[0-9]+|[^A-Za-z0-9]+');

    for (final match in regex.allMatches(input)) {
      final token = match.group(0)!;
      final upperToken = token.toUpperCase();

      if (RegExp(r'^[A-Za-z]+$').hasMatch(token) && _monthNumber(upperToken) != null) {
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

    final normalized = repaired.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    if (RegExp(r'^\d{1,2}\s+\d{1,2}\s+\d{2,4}$').hasMatch(normalized)) {
      return normalized.replaceAll(RegExp(r'\s+'), '/');
    }

    return normalized;
  }

  static String _cleanMonthYear(String value, {bool expiry = false}) {
    final parts = value.trim().replaceAll('.', '/').replaceAll('-', '/').split(RegExp(r'[/\s]+'));
    if (parts.length != 2) return value.trim();
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first != null && second != null) {
      final year = second < 100 ? 2000 + second : second;
      final month = first;
      final day = expiry ? DateTime(year, month + 1, 0).day : 1;
      return '$day/$month/$year';
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
      'JAN': 1, 'JANUARY': 1, 'FEB': 2, 'FEBRUARY': 2, 'MAR': 3,
      'MARCH': 3, 'APR': 4, 'APRIL': 4, 'MAY': 5, 'JUN': 6, 'JUNE': 6,
      'JUL': 7, 'JULY': 7, 'AUG': 8, 'AUGUST': 8, 'SEP': 9,
      'SEPTEMBER': 9, 'OCT': 10, 'OCTOBER': 10, 'NOV': 11,
      'NOVEMBER': 11, 'DEC': 12, 'DECEMBER': 12,
    };
    return months[value.toUpperCase()];
  }

  static bool _isValidDateString(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 2000 || year > 2100) return false;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static bool _containsWord(String text, String phrase) {
    final escaped = RegExp.escape(phrase).replaceAll(r'\ ', r'\s+');
    return RegExp(r'(^|[^A-Z0-9])' + escaped + r'([^A-Z0-9]|$)', caseSensitive: false).hasMatch(text);
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
      r'biscuit|chip|snack|chocolate|cookie|kurkure|lays|noodles',
    ).hasMatch(n)) {
      return 'Snacks';
    }

    if (RegExp(
      r'coke|juice|water|tea|coffee|drink|pepsi|soda',
    ).hasMatch(n)) {
      return 'Beverages';
    }

    if (RegExp(
      r'soap|shampoo|detergent|cleaner|surf|ariel',
    ).hasMatch(n)) {
      return 'Household';
    }

    if (RegExp(
      r'oil|salt|sugar|masala|spice|sauce|ketchup|jam',
    ).hasMatch(n)) {
      return 'Groceries';
    }

    return 'Others';
  }
}