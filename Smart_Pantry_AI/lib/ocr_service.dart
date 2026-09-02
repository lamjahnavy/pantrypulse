class OCRService {
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

    final commonBrands = [
      'AMUL', 'NESTLE', 'MAGGI', 'BRITANNIA', 'TATA', 'HALDIRAM',
      'AASHIRVAAD', 'DABUR', 'PARLE', 'ITC', 'CADBURY', 'PANTENE',
      'DOVE', 'SURF EXCEL', 'ARIEL', 'COLGATE', 'PEPSODENT',
      'HORLICKS', 'BOURNVITA', 'MTR', 'EVEREST', 'MDH', 'FORTUNE',
      'SAFFOLA', 'KELLOGGS', 'PEPSI', 'COKE', 'LAYS', 'KURKURE',
      'PARLE AGRO', 'MOTHER DAIRY', 'NANDINI', 'HERITAGE', 'AACHI',
      'PRIYA',
    ];

    for (final line in validLines) {
      final upper = line.toUpperCase();

      final matchingBrand = commonBrands.firstWhere(
        (brandName) => upper.contains(brandName),
        orElse: () => '',
      );

      if (matchingBrand.isNotEmpty) {
        brand = matchingBrand;
        break;
      }
    }

    final groceryKeywords = [
      'MILK', 'CURD', 'PANEER', 'BUTTER', 'CHEESE', 'GHEE',
      'ATTA', 'RICE', 'DAL', 'PULSE', 'SALT', 'SUGAR', 'OIL',
      'COFFEE', 'TEA', 'JUICE', 'SODA', 'CHIPS', 'BISCUIT',
      'COOKIE', 'JAM', 'KETCHUP', 'SAUCE', 'NOODLES', 'PASTA',
      'WHEAT', 'FLOUR', 'CEREAL', 'OATS', 'SPICE', 'MASALA',
      'SNACK', 'CHOCOLATE', 'SOAP', 'SHAMPOO', 'DETERGENT',
      'CLEANER', 'BIRYANI', 'MAGGI',
    ];

    for (final line in validLines) {
      final upper = line.toUpperCase();

      if (groceryKeywords.any(
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

        if (cleaned.length >= 3 &&
            !_looksLikeDate(cleaned) &&
            !_looksLikeQuantity(cleaned) &&
            !_looksLikePrice(cleaned) &&
            cleaned.toUpperCase() != brand.toUpperCase()) {
          name = cleaned;
          break;
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

    final dateExpression =
        r'(\d{1,2}\s*[/\-\.]\s*\d{1,2}\s*[/\-\.]\s*\d{2,4}'
        r'|\d{1,2}\s+\d{1,2}\s+\d{2,4})';

    final expiryRegex = RegExp(
      r'(?:EXP(?:IRY)?|EXPIRATION|USE\s*BY|BEST\s*BEFORE|BB)'
      r'[\s\.\-:#]*'
      '$dateExpression',
      caseSensitive: false,
    );

    final expiryMatch = expiryRegex.firstMatch(normalizedText);

    if (expiryMatch != null) {
      exp = _cleanDate(expiryMatch.group(1)!);
    }

    final mfdRegex = RegExp(
      r'(?:MFD|MFG|MFG\s*DATE|MANUFACTURED|PKD|PACKED|PACKING)'
      r'[\s\.\-:#]*'
      '$dateExpression',
      caseSensitive: false,
    );

    final mfdMatch = mfdRegex.firstMatch(normalizedText);

    if (mfdMatch != null) {
      mfd = _cleanDate(mfdMatch.group(1)!);
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();

      final isExpiryLabel =
          line.contains('EXP') ||
          line.contains('EXPIRY') ||
          line.contains('BEST BEFORE') ||
          line.contains('USE BY');

      final isMfdLabel =
          line.contains('MFD') ||
          line.contains('MFG') ||
          line.contains('MANUFACT') ||
          line.contains('PKD') ||
          line.contains('PACKED');

      if (i + 1 < lines.length) {
        final nextDate = RegExp(
          dateExpression,
          caseSensitive: false,
        ).firstMatch(lines[i + 1]);

        if (nextDate != null) {
          if (isExpiryLabel && exp == 'Not detected') {
            exp = _cleanDate(nextDate.group(1)!);
          }

          if (isMfdLabel && mfd == 'Not detected') {
            mfd = _cleanDate(nextDate.group(1)!);
          }
        }
      }
    }

    final quantityRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*'
      r'(kg|kgs|g|gm|mg|l|lt|ltr|ml|pcs|pc|units|unit|pkt|pack|packs)',
      caseSensitive: false,
    );

    for (final match in quantityRegex.allMatches(normalizedText)) {
      final value = double.tryParse(match.group(1)!);

      if (value != null && value > 0 && value < 2000) {
        quantity = match.group(0)!
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        break;
      }
    }

    final priceRegex = RegExp(
      r'(?:MRP|MAX(?:IMUM)?\s*RETAIL\s*PRICE|PRICE)'
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
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
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
    return date
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('.', '/')
        .replaceAll('-', '/');
  }

  static String _cleanup(String input) {
    return input
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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