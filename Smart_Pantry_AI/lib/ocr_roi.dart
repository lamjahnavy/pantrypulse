import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OCRRegionOfInterest {
  static const double guideWidth = 310;
  static const double guideHeight = 260;

  static Future<String?> cropGuideRegion({
    required String sourcePath,
    required double previewWidth,
    required double previewHeight,
  }) async {
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

      final cropLeft = ((guideLeft - offsetX) / scale).round().clamp(0, decoded.width - 1);
      final cropTop = ((guideTop - offsetY) / scale).round().clamp(0, decoded.height - 1);
      final cropRight = ((guideLeft + guideWidth - offsetX) / scale).round().clamp(1, decoded.width);
      final cropBottom = ((guideTop + guideHeight - offsetY) / scale).round().clamp(1, decoded.height);

      final cropWidth = (cropRight - cropLeft).clamp(1, decoded.width - cropLeft);
      final cropHeight = (cropBottom - cropTop).clamp(1, decoded.height - cropTop);
      final cropped = img.copyCrop(
        decoded,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );

      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}${Platform.pathSeparator}ocr_roi_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(img.encodeJpg(cropped, quality: 90));
      return output.path;
    } catch (_) {
      return null;
    }
  }
}
