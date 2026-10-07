import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

class DetectedObjectSize {
  final double widthPx;
  final double heightPx;

  const DetectedObjectSize({
    required this.widthPx,
    required this.heightPx,
  });
}

class OpenCvObjectDetector {
  static Future<DetectedObjectSize?> detectObject(
      Uint8List imageBytes,
      ) async {
    // Convert JPEG bytes into OpenCV Mat.
    final image = cv.imdecode(
      imageBytes,
      cv.IMREAD_COLOR,
    );

    // if (image.empty()) {
    //   return null;
    // }
    if (image.rows == 0 || image.cols == 0) {
      return null;
    }
    // Convert to grayscale.
    final gray = cv.cvtColor(
      image,
      cv.COLOR_BGR2GRAY,
    );

    // Threshold.
    final (_, binary) = cv.threshold(
      gray,
      100,
      255,
      cv.THRESH_BINARY_INV,
    );

    // Find contours.
    final (contours, _) = cv.findContours(
      binary,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    if (contours.isEmpty) {
      return null;
    }

    double largestArea = 0;
    cv.Rect? bestRect;

    for (final contour in contours) {
      final area = cv.contourArea(contour);

      if (area > largestArea) {
        largestArea = area;

        final rect = cv.boundingRect(contour);

        bestRect = rect;
      }
    }

    if (bestRect == null) {
      return null;
    }

    return DetectedObjectSize(
      widthPx: bestRect.width.toDouble(),
      heightPx: bestRect.height.toDouble(),
    );
  }
}