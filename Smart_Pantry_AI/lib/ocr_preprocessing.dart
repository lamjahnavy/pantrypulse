import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OCRPreprocessor {
  static Future<List<String>> createVariantCopies(String sourcePath) async {
    try {
      final source = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(source);
      if (decoded == null) return const [];
      img.bakeOrientation(decoded);

      final maxDimension = 1280;
      final largestDimension = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final normalized = largestDimension > maxDimension
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? maxDimension
                  : (decoded.width * maxDimension / decoded.height).round(),
              height: decoded.height >= decoded.width
                  ? maxDimension
                  : (decoded.height * maxDimension / decoded.width).round(),
              interpolation: img.Interpolation.linear,
            )
          : decoded;

      final grayscale = img.grayscale(normalized);
      img.adjustColor(grayscale, contrast: 1.12, brightness: 1.04);

      final sharpened = img.copyResize(
        grayscale,
        width: grayscale.width,
        height: grayscale.height,
        interpolation: img.Interpolation.linear,
      );
      final enhanced = img.copyResize(
        normalized,
        width: normalized.width,
        height: normalized.height,
        interpolation: img.Interpolation.linear,
      );
      img.adjustColor(enhanced, contrast: 1.18, brightness: 1.02);

      final directory = await getTemporaryDirectory();
      final variants = <String>[];
      final variantsToWrite = <({String name, img.Image image})>[
        (name: 'original', image: normalized),
        (name: 'grayscale_contrast', image: grayscale),
        (name: 'enhanced', image: enhanced),
        (name: 'sharpened', image: sharpened),
      ];

      for (final entry in variantsToWrite) {
        final output = File(
          '${directory.path}${Platform.pathSeparator}ocr_${entry.name}_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await output.writeAsBytes(img.encodeJpg(entry.image, quality: 88));
        variants.add(output.path);
      }

      return variants;
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> createEnhancedCopy(String sourcePath) async {
    try {
      final source = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(source);
      if (decoded == null) return null;
      img.bakeOrientation(decoded);

      const maxDimension = 1600;
      final largestDimension = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final normalized = largestDimension > maxDimension
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? maxDimension
                  : (decoded.width * maxDimension / decoded.height).round(),
              height: decoded.height >= decoded.width
                  ? maxDimension
                  : (decoded.height * maxDimension / decoded.width).round(),
              interpolation: img.Interpolation.linear,
            )
          : decoded;
      img.adjustColor(normalized, contrast: 1.12, brightness: 1.02);

      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}${Platform.pathSeparator}ocr_enhanced_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(img.encodeJpg(normalized, quality: 88));
      return output.path;
    } catch (_) {
      return null;
    }
  }
}