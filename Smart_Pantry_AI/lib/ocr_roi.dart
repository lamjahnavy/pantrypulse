import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OCRRegionOfInterest {
  static const double guideWidth = 310;
  static const double guideHeight = 260;
  static Map<String, double> lastTimingsMs = const {};

  static Future<double?> measureSharpness(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      img.bakeOrientation(decoded);

      final scale = decoded.width > 800 ? 800 / decoded.width : 1.0;
      final width = (decoded.width * scale).round().clamp(3, decoded.width);
      final height = (decoded.height * scale).round().clamp(3, decoded.height);
      final sampled = scale == 1.0
          ? decoded
          : img.copyResize(decoded, width: width, height: height);

      double sum = 0;
      double sumSquared = 0;
      var count = 0;
      for (var y = 1; y < sampled.height - 1; y++) {
        for (var x = 1; x < sampled.width - 1; x++) {
          final center = _luminance(sampled.getPixel(x, y));
          final laplacian = 4 * center -
              _luminance(sampled.getPixel(x - 1, y)) -
              _luminance(sampled.getPixel(x + 1, y)) -
              _luminance(sampled.getPixel(x, y - 1)) -
              _luminance(sampled.getPixel(x, y + 1));
          sum += laplacian;
          sumSquared += laplacian * laplacian;
          count++;
        }
      }
      if (count == 0) return null;
      final mean = sum / count;
      return (sumSquared / count) - (mean * mean);
    } catch (_) {
      return null;
    }
  }

  static double _luminance(img.Pixel pixel) {
    return (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
  }

  static Future<String?> cropGuideRegion({
    required String sourcePath,
    required double previewWidth,
    required double previewHeight,
  }) async {
    lastTimingsMs = const {};
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || previewWidth <= 0 || previewHeight <= 0) {
        return null;
      }

      img.bakeOrientation(decoded);

      final imageRatio = decoded.width / decoded.height;
      final previewRatio = previewWidth / previewHeight;
      final scale = imageRatio > previewRatio
          ? previewHeight / decoded.height
          : previewWidth / decoded.width;

      final imageDisplayWidth = decoded.width * scale;
      final imageDisplayHeight = decoded.height * scale;
      final offsetX = (previewWidth - imageDisplayWidth) / 2;
      final offsetY = (previewHeight - imageDisplayHeight) / 2;

      final guideLeft = (previewWidth - guideWidth) / 2;
      final guideTop = (previewHeight - guideHeight) / 2;

      final cropLeft =
          ((guideLeft - offsetX) / scale).round().clamp(0, decoded.width - 1);
      final cropTop =
          ((guideTop - offsetY) / scale).round().clamp(0, decoded.height - 1);
      final cropRight = ((guideLeft + guideWidth - offsetX) / scale)
          .round()
          .clamp(1, decoded.width);
      final cropBottom = ((guideTop + guideHeight - offsetY) / scale)
          .round()
          .clamp(1, decoded.height);

      final cropWidth =
          (cropRight - cropLeft).clamp(1, decoded.width - cropLeft);
      final cropHeight =
          (cropBottom - cropTop).clamp(1, decoded.height - cropTop);
      final cropStarted = DateTime.now();
      final cropped = img.copyCrop(
        decoded,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );
      final cropMs =
          DateTime.now().difference(cropStarted).inMicroseconds / 1000.0;

      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}${Platform.pathSeparator}ocr_roi_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      final encodeStarted = DateTime.now();
      final encoded = img.encodeJpg(cropped, quality: 92);
      final encodeMs =
          DateTime.now().difference(encodeStarted).inMicroseconds / 1000.0;
      await output.writeAsBytes(encoded);
      lastTimingsMs = {
        'roi_crop_ms': cropMs,
        'jpeg_encode_ms': encodeMs,
      };
      return output.path;
    } catch (_) {
      return null;
    }
  }
}

class OCRTemporaryFileLease {
  OCRTemporaryFileLease([this.path]);

  String? path;

  Future<void> dispose() async {
    final filePath = path;
    path = null;
    if (filePath == null) return;
    try {
      await File(filePath).delete();
    } on FileSystemException {
      // The cache may already have removed the file; cleanup is idempotent.
    }
  }
}
